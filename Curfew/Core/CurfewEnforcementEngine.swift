import Foundation

public enum EnforcementPhase: Equatable {
    case working
    case warning
    case locked
    case dayOff
}

public struct CurfewEvaluation: Equatable {
    public var phase: EnforcementPhase
    public var warningStage: WarningStage
    public var minutesRemaining: Int
    public var canRequestExtension: Bool
    public var lockDate: Date?
    public var unlockDate: Date?

    public static let dayOff = CurfewEvaluation(
        phase: .dayOff,
        warningStage: .none,
        minutesRemaining: .max,
        canRequestExtension: false,
        lockDate: nil,
        unlockDate: nil
    )

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

public struct CurfewEnforcementEngine {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

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

        if let overrideUntil, date < overrideUntil {
            return workingWithOverride(
                at: date,
                window: window,
                intervals: warningIntervals
            )
        }

        if date >= window.lockDate, date < window.unlockDate {
            return .locked(lockDate: window.lockDate, unlockDate: window.unlockDate)
        }

        return approachingLock(
            at: date,
            window: window,
            intervals: warningIntervals
        )
    }

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

    private func remainingMinutes(until lockDate: Date, from date: Date) -> Int {
        let secondsRemaining = lockDate.timeIntervalSince(date)
        guard secondsRemaining > 0 else {
            return 0
        }
        return Int(ceil(secondsRemaining / 60.0))
    }
}

private extension WarningStage {
    var allowsExtensionRequest: Bool {
        self == .thirtyMinutes || self == .fifteenMinutes
    }
}
