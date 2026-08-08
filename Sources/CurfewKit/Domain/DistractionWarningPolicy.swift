import Foundation

/// Decides whether Curfew should nudge a user who is at the machine but not
/// working.
///
/// This is the policy behind the founding claim "if I am distracted, Curfew
/// will warn me to get back to work". It is pure — no timers, no notification
/// centre, no camera — so every branch is reachable from a test with three
/// dates and an enum.
///
/// The interesting decisions are the ones that produce *silence*:
///
/// - **Only ``PresenceState/presentButIdle`` counts as distraction.** An
///   ``PresenceState/absent`` user is not distracted, they are gone, and a
///   banner fired at an empty chair is noise the user discovers ten minutes
///   later. An ``PresenceState/unknown`` user is one Curfew has no camera
///   signal for, and guessing there would make the nudge fire constantly on a
///   default install where the camera is off.
/// - **Never during lockout or a day off.** During lockout the screen is
///   already covering the Mac and "get back to work" is the opposite of the
///   instruction. On a day off there is no work to get back to.
/// - **Never immediately.** A pause has to be sustained before it is a
///   distraction; standing up to stretch is not one.
public struct DistractionWarningPolicy: Equatable, Sendable {
    /// Why a nudge was withheld. Carried on the verdict so the audit log and
    /// tests can state the reason rather than infer it from silence.
    public enum HoldReason: String, Equatable, Sendable {
        /// The user turned distraction nudges off, or presence detection is
        /// off entirely so there is no signal to act on.
        case disabled

        /// The fused state is not ``PresenceState/presentButIdle``.
        case notDistracted = "not_distracted"

        /// Lockout or a day off — the wrong moment to ask for focus.
        case phaseNotEligible = "phase_not_eligible"

        /// Present-but-idle, but not for long enough yet.
        case tooBrief = "too_brief"

        /// Long enough, but a nudge already went out inside the repeat window.
        case recentlyWarned = "recently_warned"
    }

    /// The outcome of one evaluation.
    public enum Verdict: Equatable, Sendable {
        /// Deliver a nudge now.
        case warn

        /// Stay quiet, for this reason.
        case hold(HoldReason)

        /// Whether this verdict calls for a notification.
        public var isWarn: Bool {
            self == .warn
        }
    }

    /// Longest a nudge may be delayed, applied on decode as well as on
    /// construction. A "sustained" window measured in hours would mean the
    /// feature silently never fires.
    public static let sustainedCeilingSeconds = 3600

    /// Floor on the sustained window. Anything shorter fires while the user is
    /// still mid-thought, which trains them to ignore it.
    public static let sustainedFloorSeconds = 60

    /// Floor on the repeat interval, so a persistent distraction cannot turn
    /// into a notification storm.
    public static let repeatFloorSeconds = 120

    /// Ceiling on the repeat interval.
    public static let repeatCeilingSeconds = 7200

    /// How long the user must stay present-but-idle before the first nudge.
    public let sustainedSeconds: TimeInterval

    /// Minimum gap between nudges while a single distraction persists.
    public let repeatSeconds: TimeInterval

    /// Creates a policy, clamping both windows into their supported ranges so
    /// a hand-edited settings file cannot disable the feature by arithmetic.
    public init(sustainedSeconds: Int, repeatSeconds: Int) {
        self.sustainedSeconds = TimeInterval(Self.clampSustained(sustainedSeconds))
        self.repeatSeconds = TimeInterval(Self.clampRepeat(repeatSeconds))
    }

    /// Decides whether to nudge.
    ///
    /// - Parameters:
    ///   - state: The fused presence state right now.
    ///   - phase: The current enforcement phase.
    ///   - stateEnteredAt: When `state` began. Compared against `now` to
    ///     measure how long the distraction has lasted.
    ///   - lastWarnedAt: When the last nudge was delivered, or
    ///     ``Date/distantPast`` if none has been. A sentinel rather than an
    ///     optional so the repeat-window arithmetic needs no special case.
    ///   - now: The moment being evaluated.
    ///   - isEnabled: Whether the user wants nudges *and* presence detection
    ///     is actually running. A caller must fold both in; this policy will
    ///     not infer consent from the presence state.
    /// - Returns: ``Verdict/warn`` or ``Verdict/hold(_:)`` with the reason.
    public func decide(
        state: PresenceState,
        phase: EnforcementPhase,
        stateEnteredAt: Date,
        lastWarnedAt: Date,
        now: Date,
        isEnabled: Bool
    ) -> Verdict {
        guard isEnabled else {
            return .hold(.disabled)
        }
        guard state == .presentButIdle else {
            return .hold(.notDistracted)
        }
        guard Self.isEligible(phase) else {
            return .hold(.phaseNotEligible)
        }
        guard now.timeIntervalSince(stateEnteredAt) >= sustainedSeconds else {
            return .hold(.tooBrief)
        }
        guard now.timeIntervalSince(lastWarnedAt) >= repeatSeconds else {
            return .hold(.recentlyWarned)
        }
        return .warn
    }

    /// Phases in which a "get back to work" nudge makes sense: the ordinary
    /// working day and the warning run-up to curfew. Explicitly listed rather
    /// than expressed as "not locked" so adding a phase later forces a
    /// decision here instead of silently opting in.
    public static func isEligible(_ phase: EnforcementPhase) -> Bool {
        switch phase {
        case .working, .warning: true
        case .locked, .dayOff: false
        }
    }

    /// Default cadence: three minutes of stillness before the first nudge,
    /// then at most one every ten minutes.
    ///
    /// Three minutes is long enough to sit out a paragraph of reading or a
    /// short phone call, and short enough that the nudge still lands inside
    /// the drift it is trying to interrupt. Ten minutes between repeats means
    /// a genuinely long meeting produces a handful of banners across an
    /// afternoon rather than one every three minutes.
    public static let `default` = DistractionWarningPolicy(
        sustainedSeconds: 180,
        repeatSeconds: 600
    )

    private static func clampSustained(_ seconds: Int) -> Int {
        min(max(sustainedFloorSeconds, seconds), sustainedCeilingSeconds)
    }

    private static func clampRepeat(_ seconds: Int) -> Int {
        min(max(repeatFloorSeconds, seconds), repeatCeilingSeconds)
    }
}
