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

    /// Pre-built day-off evaluation. All timing fields are zeroed / nil.
    public static let dayOff = CurfewEvaluation(
        phase: .dayOff,
        warningStage: .none,
        minutesRemaining: .max,
        canRequestExtension: false,
        lockDate: nil,
        unlockDate: nil
    )

    /// Pre-built locked evaluation with absolute lock / unlock dates.
    /// `minutesRemaining` is 0 and `canRequestExtension` is false during
    /// lockout.
    public static func locked(lockDate: Date, unlockDate: Date) -> CurfewEvaluation {
        CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: lockDate,
            unlockDate: unlockDate
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
    public func evaluate(
        at date: Date,
        schedule: WeeklySchedule,
        extensionMinutesGrantedToday: Int,
        overrideUntil: Date?,
        warningIntervals: WarningIntervals = .default
    ) -> CurfewEvaluation {
        guard let window = schedule.scheduleWindow(
            for: date,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday,
            calendar: calendar
        ) else {
            return .dayOff
        }

        let intervals = warningIntervals.normalized

        if let overrideUntil, date < overrideUntil {
            return workingWithOverride(
                at: date,
                window: window,
                intervals: intervals
            )
        }

        if date >= window.lockDate, date < window.unlockDate {
            return .locked(lockDate: window.lockDate, unlockDate: window.unlockDate)
        }

        return approachingLock(
            at: date,
            window: window,
            intervals: intervals
        )
    }

    /// Evaluation during an active override: the phase stays `.working` but
    /// warning stages still escalate so the user can see their real deadline
    /// approaching even while the override is in effect.
    private func workingWithOverride(
        at date: Date,
        window: ScheduleWindow,
        intervals: WarningIntervals
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
            unlockDate: window.unlockDate
        )
    }

    /// Evaluation outside the locked window: maps minutes-remaining to a
    /// phase (`.working` or `.warning`) and a ``WarningStage``.
    private func approachingLock(
        at date: Date,
        window: ScheduleWindow,
        intervals: WarningIntervals
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
                unlockDate: window.unlockDate
            )
        case .lockout:
            return .locked(lockDate: window.lockDate, unlockDate: window.unlockDate)
        default:
            return CurfewEvaluation(
                phase: .warning,
                warningStage: stage,
                minutesRemaining: minutesRemaining,
                canRequestExtension: stage.allowsExtensionRequest,
                lockDate: window.lockDate,
                unlockDate: window.unlockDate
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
