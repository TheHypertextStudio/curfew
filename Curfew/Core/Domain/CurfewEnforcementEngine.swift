import Foundation

/// The broad enforcement state of the device at a given moment.
///
/// The tick loop maps `EnforcementPhase` to overlay visibility, menu bar
/// icon colour, and lockout window presentation. It is intentionally coarse
/// — fine-grained warning timing lives in ``WarningStage``, which is
/// orthogonal to phase.
public enum EnforcementPhase: Equatable {
    /// The user is within their permitted working window. No overlay is shown.
    case working

    /// The lock time is approaching. A translucent dim overlay is shown;
    /// the floating timer appears at T-5 and below.
    case warning

    /// The working window has ended. The full-screen lockout is shown and
    /// keyboard shortcuts are intercepted.
    case locked

    /// Today has no enforcement window (weekend, holiday, or user-configured
    /// day off). No enforcement actions are taken.
    case dayOff
}

/// What caused the current countdown. For `.time` the answer is always
/// `.time`; for `.hours` it's always `.hours`; for `.combined` it's whichever
/// deadline fires first — i.e. the nearer of the two.
///
/// The MCP `get_time_remaining` tool surfaces this so AI assistants can
/// phrase the answer correctly ("you have 14 minutes before your 6 PM
/// curfew" vs. "you have 14 minutes of work hours left today").
public enum EnforcementTrigger: String, Equatable, Codable {
    case time
    case hours
}

/// The complete output of a single enforcement evaluation for a given moment.
///
/// The engine is a pure function: same inputs → same `CurfewEvaluation`. The
/// app model caches the latest evaluation in `state` and feeds it to every
/// downstream consumer (overlay coordinator, notification manager, snapshot).
///
/// Two convenience factories cover the most common non-computed cases:
/// ``dayOff`` for days without an enforcement window, and ``locked(lockDate:unlockDate:)``
/// for the lockout phase.
public struct CurfewEvaluation: Equatable {
    /// Broad enforcement state for this tick.
    public var phase: EnforcementPhase

    /// Fine-grained warning escalation stage. ``WarningStage/none`` outside
    /// warning + lockout phases.
    public var warningStage: WarningStage

    /// Minutes remaining until the lock time fires. `Int.max` when there is
    /// no upcoming lock (day off, already locked). `0` during lockout.
    public var minutesRemaining: Int

    /// Whether the "Hold for extension" button should be active. True only
    /// during the T-30 and T-15 warning stages when the weekly budget is not
    /// yet exhausted.
    public var canRequestExtension: Bool

    /// The absolute date when the device will lock today, or `nil` on day-off.
    public var lockDate: Date?

    /// The absolute date when the device will unlock the following morning,
    /// or `nil` on day-off.
    public var unlockDate: Date?

    /// Which clock is driving the current countdown — wall time or
    /// accumulated work hours. In `.time` mode this is always `.time`;
    /// in combined mode it's whichever deadline fires first.
    public var trigger: EnforcementTrigger

    /// Memberwise initialiser with a back-compat default for `trigger`
    /// so pre-v0.2 construction sites (tests, legacy snapshots) keep
    /// compiling without having to specify the new field.
    public init(
        phase: EnforcementPhase,
        warningStage: WarningStage,
        minutesRemaining: Int,
        canRequestExtension: Bool,
        lockDate: Date?,
        unlockDate: Date?,
        trigger: EnforcementTrigger = .time
    ) {
        self.phase = phase
        self.warningStage = warningStage
        self.minutesRemaining = minutesRemaining
        self.canRequestExtension = canRequestExtension
        self.lockDate = lockDate
        self.unlockDate = unlockDate
        self.trigger = trigger
    }

    /// Pre-built day-off evaluation. All timing fields are zeroed / nil.
    public static let dayOff = CurfewEvaluation(
        phase: .dayOff,
        warningStage: .none,
        minutesRemaining: .max,
        canRequestExtension: false,
        lockDate: nil,
        unlockDate: nil,
        trigger: .time
    )

    /// Pre-built locked evaluation with absolute lock / unlock dates.
    /// `minutesRemaining` is 0 and `canRequestExtension` is false during
    /// lockout. Callers specify `trigger` so the lockout screen can tell
    /// the user whether time or hours pushed them over.
    public static func locked(
        lockDate: Date,
        unlockDate: Date,
        trigger: EnforcementTrigger = .time
    ) -> CurfewEvaluation {
        CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: lockDate,
            unlockDate: unlockDate,
            trigger: trigger
        )
    }
}

/// Pure-function engine that maps (schedule, now, extensions, override) →
/// ``CurfewEvaluation``.
///
/// The engine has no state and no side effects. All inputs are passed
/// explicitly so the engine is trivially testable: pin a `Calendar`, supply
/// a fixed `date`, and assert the output directly. `CurfewAppModel` holds
/// one long-lived engine instance and calls
/// ``evaluate(at:schedule:extensionMinutesGrantedToday:overrideUntil:warningIntervals:)``
/// once per tick.
public struct CurfewEnforcementEngine {
    private let calendar: Calendar

    /// Creates an engine that uses `calendar` for all date arithmetic.
    /// Defaults to `Calendar.current` for production; tests pin a fixed UTC
    /// calendar to avoid DST and timezone drift.
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Evaluates the enforcement state at `date`.
    ///
    /// - Parameters:
    ///   - date: The moment to evaluate — typically `Date()` from the 1 Hz tick.
    ///   - schedule: The active weekly curfew schedule.
    ///   - extensionMinutesGrantedToday: Cumulative extension minutes already
    ///     consumed today; added to the lock time before comparison.
    ///   - overrideUntil: When non-nil, the engine returns `.working` for the
    ///     duration of the override even if the nominal lock time has passed.
    ///   - warningIntervals: Thresholds for each escalation stage. Defaults to
    ///     ``WarningIntervals/default``.
    ///   - workedMinutesToday: Active work minutes accumulated today across
    ///     every synced device (idle time excluded). Only consulted when the
    ///     day's rule is in `.hours` or `.combined` mode; defaults to 0 so
    ///     existing call sites that pre-date the feature keep working.
    public func evaluate(
        at date: Date,
        schedule: WeeklySchedule,
        extensionMinutesGrantedToday: Int,
        overrideUntil: Date?,
        warningIntervals: WarningIntervals = .default,
        workedMinutesToday: Int = 0
    ) -> CurfewEvaluation {
        guard let window = schedule.scheduleWindow(
            for: date,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday,
            calendar: calendar
        ) else {
            return .dayOff
        }

        // Compute the effective window when hours-based enforcement is in
        // play. For `.time` rules this is unchanged; for `.hours` the
        // lock time becomes "now + (limit - worked)"; for `.combined`
        // it's the nearer of the two. The `trigger` field flows through
        // so the UI can tell the user which clock fired.
        let weekday = Weekday(from: date, calendar: calendar)
        let rule = schedule.rule(for: weekday)
        let adjusted = applyHoursMode(
            window: window,
            rule: rule,
            at: date,
            workedMinutesToday: workedMinutesToday,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday
        )

        let intervals = warningIntervals.normalized

        if let overrideUntil, date < overrideUntil {
            return workingWithOverride(
                at: date,
                window: adjusted.window,
                intervals: intervals,
                trigger: adjusted.trigger
            )
        }

        if date >= adjusted.window.lockDate, date < adjusted.window.unlockDate {
            return .locked(
                lockDate: adjusted.window.lockDate,
                unlockDate: adjusted.window.unlockDate,
                trigger: adjusted.trigger
            )
        }

        return approachingLock(
            at: date,
            window: adjusted.window,
            intervals: intervals,
            trigger: adjusted.trigger
        )
    }

    /// For `.hours` and `.combined` rules, recomputes the effective lock
    /// time from accumulated work minutes. For `.time` rules returns the
    /// original window and `.time` trigger unchanged.
    ///
    /// The hours deadline is "current time + (hoursLimit + extensions -
    /// worked)". Extensions apply to **both** clocks — the wall deadline
    /// already reflects them via `schedule.scheduleWindow(extensionMinutes…)`,
    /// and the hours budget grows by the same amount here. Rationale: a
    /// user who requests "+15 min" in any mode means "15 more minutes
    /// tonight"; pushing both deadlines honors that regardless of which
    /// clock is about to fire. Combined mode still picks the nearer of
    /// the two post-extension deadlines.
    private func applyHoursMode(
        window: ScheduleWindow,
        rule: DayRule,
        at date: Date,
        workedMinutesToday: Int,
        extensionMinutesGrantedToday: Int
    ) -> (window: ScheduleWindow, trigger: EnforcementTrigger) {
        guard rule.mode != .time,
              let hoursLimit = rule.hoursLimitMinutes,
              hoursLimit > 0
        else {
            return (window, .time)
        }
        let effectiveLimit = hoursLimit + max(0, extensionMinutesGrantedToday)
        let minutesLeft = max(0, effectiveLimit - workedMinutesToday)
        let hoursDeadline = date.addingTimeInterval(TimeInterval(minutesLeft * 60))

        switch rule.mode {
        case .hours:
            return (
                ScheduleWindow(lockDate: hoursDeadline, unlockDate: window.unlockDate),
                .hours
            )
        case .combined:
            if hoursDeadline < window.lockDate {
                return (
                    ScheduleWindow(lockDate: hoursDeadline, unlockDate: window.unlockDate),
                    .hours
                )
            }
            return (window, .time)
        case .time:
            return (window, .time)
        }
    }

    /// Evaluation during an active override: the phase stays `.working` but
    /// warning stages still escalate so the user can see their real deadline
    /// approaching even while the override is in effect.
    private func workingWithOverride(
        at date: Date,
        window: ScheduleWindow,
        intervals: WarningIntervals,
        trigger: EnforcementTrigger
    ) -> CurfewEvaluation {
        let minutesRemaining = remainingMinutes(until: window.lockDate, from: date)
        let stage = WarningStage.stage(
            forMinutesRemaining: minutesRemaining,
            intervals: intervals
        )
        return CurfewEvaluation(
            phase: .working,
            warningStage: stage,
            minutesRemaining: minutesRemaining,
            canRequestExtension: stage.allowsExtensionRequest,
            lockDate: window.lockDate,
            unlockDate: window.unlockDate,
            trigger: trigger
        )
    }

    /// Evaluation outside the locked window: maps minutes-remaining to a
    /// phase (`.working` or `.warning`) and a ``WarningStage``.
    private func approachingLock(
        at date: Date,
        window: ScheduleWindow,
        intervals: WarningIntervals,
        trigger: EnforcementTrigger
    ) -> CurfewEvaluation {
        let minutesRemaining = remainingMinutes(until: window.lockDate, from: date)
        let stage = WarningStage.stage(
            forMinutesRemaining: minutesRemaining,
            intervals: intervals
        )

        switch stage {
        case .none:
            return CurfewEvaluation(
                phase: .working,
                warningStage: .none,
                minutesRemaining: minutesRemaining,
                canRequestExtension: false,
                lockDate: window.lockDate,
                unlockDate: window.unlockDate,
                trigger: trigger
            )
        case .lockout:
            return .locked(
                lockDate: window.lockDate,
                unlockDate: window.unlockDate,
                trigger: trigger
            )
        default:
            return CurfewEvaluation(
                phase: .warning,
                warningStage: stage,
                minutesRemaining: minutesRemaining,
                canRequestExtension: stage.allowsExtensionRequest,
                lockDate: window.lockDate,
                unlockDate: window.unlockDate,
                trigger: trigger
            )
        }
    }

    /// Rounds up fractional minutes so T-1 fires as soon as the device enters
    /// the final 60 seconds, not only when the full minute has elapsed.
    private func remainingMinutes(until lockDate: Date, from date: Date) -> Int {
        let secondsRemaining = lockDate.timeIntervalSince(date)
        guard secondsRemaining > 0 else {
            return 0
        }
        return Int(ceil(secondsRemaining / 60.0))
    }
}

private extension WarningStage {
    /// Extension requests are allowed only at T-30 and T-15 — late enough
    /// that the warning is meaningful, early enough that the user has time
    /// to actually use the extension.
    var allowsExtensionRequest: Bool {
        self == .thirtyMinutes || self == .fifteenMinutes
    }
}
