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
        /// Whether work is in flight: an unexpired ``ProtectedWorkClaim``, or
        /// an agent process / network login ``LiveProtectedWorkMonitor``
        /// observed. `main.swift` combines both, because the agent runs that
        /// most need this are exactly the ones that never declared themselves.
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

    /// What to do, what the marker must say afterwards, and whether a
    /// shutdown already in flight has to be called off.
    public struct Outcome: Equatable, Sendable {
        /// The action to take.
        public let action: Action
        /// The value the caller must write to the deferral marker — including
        /// `nil`, which means "delete it". Writing this unconditionally is
        /// what keeps a recovered heartbeat from leaving a spent window
        /// behind.
        public let deferralStartedAt: Date?
        /// Whether the caller must kill a `/sbin/shutdown` this daemon already
        /// issued.
        ///
        /// Carried on the outcome rather than inferred by the caller because
        /// inferring it is where this went wrong: `.hold` used to only log,
        /// so a claim arriving inside the shutdown's one-minute delay was
        /// honored by the decision and ignored by the machine, which powered
        /// off anyway. Deciding to wait and forgetting to call off the wait
        /// are now the same fact.
        public let cancelsPendingShutdown: Bool

        public init(
            action: Action,
            deferralStartedAt: Date?,
            cancelsPendingShutdown: Bool = false
        ) {
            self.action = action
            self.deferralStartedAt = deferralStartedAt
            self.cancelsPendingShutdown = cancelsPendingShutdown
        }
    }

    /// Decides this tick.
    public static func evaluate(_ input: Input) -> Outcome {
        guard let deadline = input.deadline else {
            return finish(.exit, startedAt: nil, input: input)
        }
        guard input.now < deadline.scheduledUnlockAt else {
            return finish(.exit, startedAt: nil, input: input)
        }

        let isShutdownDue = input.heartbeatAge > input.heartbeatTimeout

        // Break-glass, protected work, and the bounded window are all decided
        // by `DestructiveActionGate`, which the app's `ShutdownWorkflow` also
        // consults. Nothing about "may I act?" is decided here — that is the
        // only way the two processes stay in step.
        var gate = DestructiveActionGate(
            deferralStartedAt: carriedWindowStart(input, lockoutStartedAt: deadline.lockoutStartedAt)
        )
        let decision = gate.evaluate(
            now: input.now,
            isDue: isShutdownDue,
            isBreakGlassActive: input.breakGlassActive,
            hasActiveProtectedWork: input.hasActiveProtectedWork,
            maximumDeferral: input.maximumDeferral
        )

        let started = gate.deferralStartedAt
        switch decision {
        case .standDown:
            return finish(.standDown, startedAt: started, input: input)
        case .hold(let until):
            return finish(.hold(until: until), startedAt: started, input: input)
        case .proceed:
            guard isShutdownDue, !input.shutdownAlreadyIssued else {
                return finish(.wait, startedAt: started, input: input)
            }
            return finish(.shutDown, startedAt: started, input: input)
        }
    }

    /// Packages an action with the marker value and the cancellation flag, so
    /// every return path answers the cancellation question rather than only
    /// the ones whose author remembered it.
    private static func finish(
        _ action: Action,
        startedAt: Date?,
        input: Input
    ) -> Outcome {
        Outcome(
            action: action,
            deferralStartedAt: startedAt,
            cancelsPendingShutdown: cancelsPendingShutdown(action, input: input)
        )
    }

    /// Whether a shutdown already in flight must be called off.
    ///
    /// `.hold` and `.standDown` cancel for the obvious reason: something is
    /// telling the daemon not to destroy the user's work, and a countdown
    /// already running would destroy it anyway. `.exit` cancels because the
    /// lockout window is over — powering the Mac off after a legitimate unlock
    /// is pure harm, and the bypass it buys is the sixty seconds the shutdown
    /// had left.
    ///
    /// `.wait` deliberately does not. Its main cause is the app heartbeat
    /// recovering, and cancelling there would price the bypass at nothing:
    /// kill Curfew, enjoy an unlocked screen, relaunch inside the minute, walk
    /// away with no consequence. The daemon's whole deterrent is that going
    /// missing during lockout costs you the machine.
    private static func cancelsPendingShutdown(_ action: Action, input: Input) -> Bool {
        guard input.shutdownAlreadyIssued else {
            return false
        }
        switch action {
        case .exit, .standDown, .hold:
            return true
        case .shutDown, .wait:
            return false
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
