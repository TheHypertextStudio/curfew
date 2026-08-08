import Foundation

/// One pass of the privileged daemon's decision loop, as a pure function.
///
/// The daemon is a top-level `main.swift` script, which made its logic
/// untestable and let a real bug ship: the persisted deferral marker was
/// written only on the branch where a shutdown was due, so a heartbeat that
/// recovered left a stale window behind and the *next* genuine incident in the
/// same lockout inherited an already-spent budget — no grace at all, exactly
/// the outcome the carve-out exists to prevent.
///
/// Everything the daemon decides now lives here, and `main.swift` is reduced
/// to reading files, writing files, and doing what this returns.
///
/// The invariant the caller must honor: **``Outcome/deferralStartedAt`` is
/// authoritative and must be persisted on every tick, `nil` included.** The
/// marker is a mirror of the in-memory window, never a log of windows past.
public enum DaemonEnforcementDecision {
    /// What the daemon should do this tick.
    public enum Action: Equatable, Sendable {
        /// No lockout left to enforce. Clean up and quit.
        case exit
        /// A verified break-glass release covers this window. Cancel any
        /// pending shutdown and sit quietly.
        case standDown
        /// Protected work is live and the shutdown is due. Hold it until
        /// `until` at the latest.
        case hold(until: Date)
        /// Issue the root shutdown now.
        case shutDown
        /// Nothing is due. Sleep and look again.
        case wait
    }

    /// Everything the decision reads. Grouped into a struct so the daemon's
    /// I/O and its policy stay separable, and so a test can drive a whole
    /// sequence of ticks without a filesystem.
    public struct Input: Equatable, Sendable {
        /// Current clock time.
        public var now: Date
        /// The lockout window being enforced, or `nil` when there is none.
        public var deadline: LockoutDeadlineRecord?
        /// Whether a verified release covers this window.
        public var breakGlassActive: Bool
        /// Seconds since the app last touched its heartbeat. `.infinity` when
        /// the file is missing.
        public var heartbeatAge: TimeInterval
        /// How stale the heartbeat must be before a shutdown is due.
        public var heartbeatTimeout: TimeInterval
        /// Whether any unexpired ``ProtectedWorkClaim`` exists.
        public var hasActiveProtectedWork: Bool
        /// From ``ProtectedWorkPolicy/maximumDeferral``.
        public var maximumDeferral: TimeInterval
        /// The root-owned marker's contents, or `nil` when absent.
        public var persistedDeferralStart: Date?
        /// Whether this daemon has already fired `/sbin/shutdown` for this
        /// window, so it doesn't fire twice during the one-minute delay.
        public var shutdownAlreadyIssued: Bool

        public init(
            now: Date,
            deadline: LockoutDeadlineRecord?,
            breakGlassActive: Bool = false,
            heartbeatAge: TimeInterval = 0,
            heartbeatTimeout: TimeInterval = 90,
            hasActiveProtectedWork: Bool = false,
            maximumDeferral: TimeInterval = ProtectedWorkPolicy.default.maximumDeferral,
            persistedDeferralStart: Date? = nil,
            shutdownAlreadyIssued: Bool = false
        ) {
            self.now = now
            self.deadline = deadline
            self.breakGlassActive = breakGlassActive
            self.heartbeatAge = heartbeatAge
            self.heartbeatTimeout = heartbeatTimeout
            self.hasActiveProtectedWork = hasActiveProtectedWork
            self.maximumDeferral = maximumDeferral
            self.persistedDeferralStart = persistedDeferralStart
            self.shutdownAlreadyIssued = shutdownAlreadyIssued
        }
    }

    /// What to do, and what the marker must say afterwards.
    public struct Outcome: Equatable, Sendable {
        /// The action to take.
        public let action: Action
        /// The value the caller must write to the deferral marker — including
        /// `nil`, which means "delete it". Writing this unconditionally is
        /// what keeps a recovered heartbeat from leaving a spent window
        /// behind.
        public let deferralStartedAt: Date?

        public init(action: Action, deferralStartedAt: Date?) {
            self.action = action
            self.deferralStartedAt = deferralStartedAt
        }
    }

    /// Decides this tick.
    public static func evaluate(_ input: Input) -> Outcome {
        guard let deadline = input.deadline else {
            return Outcome(action: .exit, deferralStartedAt: nil)
        }
        guard input.now < deadline.scheduledUnlockAt else {
            return Outcome(action: .exit, deferralStartedAt: nil)
        }
        guard !input.breakGlassActive else {
            return Outcome(action: .standDown, deferralStartedAt: nil)
        }

        let isShutdownDue = input.heartbeatAge > input.heartbeatTimeout

        var deferral = ProtectedWorkDeferral(
            startedAt: carriedWindowStart(input, lockoutStartedAt: deadline.lockoutStartedAt)
        )
        // The conjunction is the whole fix. A window is open only while a
        // shutdown is actually due; the moment the heartbeat recovers there is
        // nothing to defer, `ProtectedWorkDeferral` clears its own start, and
        // the caller writes that `nil` straight through to the marker.
        let decision = deferral.evaluate(
            now: input.now,
            hasActiveWork: isShutdownDue && input.hasActiveProtectedWork,
            maximumDeferral: input.maximumDeferral
        )

        switch decision {
        case .deferred(let until):
            return Outcome(action: .hold(until: until), deferralStartedAt: deferral.startedAt)
        case .proceed:
            guard isShutdownDue, !input.shutdownAlreadyIssued else {
                return Outcome(action: .wait, deferralStartedAt: deferral.startedAt)
            }
            return Outcome(action: .shutDown, deferralStartedAt: deferral.startedAt)
        }
    }

    /// The persisted window start, if it belongs to the window being enforced.
    ///
    /// The marker is root-owned and survives the daemon being killed, a
    /// reboot, or a power cut, so it can outlive the lockout that created it.
    /// A marker from Tuesday would hand Wednesday's first genuine incident a
    /// budget that expired a day ago. Scoping it to `lockoutStartedAt` is the
    /// same rule break-glass records already follow.
    ///
    /// A marker dated in the future is dropped too: a clock jump would
    /// otherwise push the deadline out by the size of the skew.
    private static func carriedWindowStart(
        _ input: Input,
        lockoutStartedAt: Date
    ) -> Date? {
        guard let persisted = input.persistedDeferralStart else {
            return nil
        }
        guard persisted >= lockoutStartedAt, persisted <= input.now else {
            return nil
        }
        return persisted
    }
}
