import Foundation

enum EnforcementPhase: Equatable, Sendable {
    case working
    case warning
    case locked
    case dayOff
}

struct CurfewEvaluation: Equatable, Sendable {
    var phase: EnforcementPhase
    var warningStage: WarningStage
    var minutesRemaining: Int
    var canRequestExtension: Bool
    var lockDate: Date?
    var unlockDate: Date?
}

struct CurfewEnforcementEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func evaluate(
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
            return CurfewEvaluation(
                phase: .dayOff,
                warningStage: .none,
                minutesRemaining: .max,
                canRequestExtension: false,
                lockDate: nil,
                unlockDate: nil
            )
        }

        let lockDate = window.lockDate
        let unlockDate = window.unlockDate

        if let overrideUntil, date < overrideUntil {
            let minutesRemaining = remainingMinutes(until: lockDate, from: date)
            let stage = WarningStage.stage(
                forMinutesRemaining: minutesRemaining,
                intervals: warningIntervals
            )
            return CurfewEvaluation(
                phase: .working,
                warningStage: stage,
                minutesRemaining: minutesRemaining,
                canRequestExtension: stage == .thirtyMinutes || stage == .fifteenMinutes,
                lockDate: lockDate,
                unlockDate: unlockDate
            )
        }

        if date >= lockDate && date < unlockDate {
            return CurfewEvaluation(
                phase: .locked,
                warningStage: .lockout,
                minutesRemaining: 0,
                canRequestExtension: false,
                lockDate: lockDate,
                unlockDate: unlockDate
            )
        }

        let minutesRemaining = remainingMinutes(until: lockDate, from: date)
        let stage = WarningStage.stage(
            forMinutesRemaining: minutesRemaining,
            intervals: warningIntervals
        )

        if stage == .none {
            return CurfewEvaluation(
                phase: .working,
                warningStage: .none,
                minutesRemaining: minutesRemaining,
                canRequestExtension: false,
                lockDate: lockDate,
                unlockDate: unlockDate
            )
        }

        if stage == .lockout {
            return CurfewEvaluation(
                phase: .locked,
                warningStage: .lockout,
                minutesRemaining: 0,
                canRequestExtension: false,
                lockDate: lockDate,
                unlockDate: unlockDate
            )
        }

        return CurfewEvaluation(
            phase: .warning,
            warningStage: stage,
            minutesRemaining: minutesRemaining,
            canRequestExtension: stage == .thirtyMinutes || stage == .fifteenMinutes,
            lockDate: lockDate,
            unlockDate: unlockDate
        )
    }

    private func remainingMinutes(until lockDate: Date, from date: Date) -> Int {
        let secondsRemaining = lockDate.timeIntervalSince(date)
        guard secondsRemaining > 0 else {
            return 0
        }
        return Int(ceil(secondsRemaining / 60.0))
    }
}
