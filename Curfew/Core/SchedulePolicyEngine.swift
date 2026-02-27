import Foundation

enum ScheduleChangeClassification: String, Equatable, Codable, Sendable {
    case weaker
    case stricter
    case noChange = "no_change"
}

struct SchedulePolicyEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func classifyChange(from current: WeeklySchedule, to proposed: WeeklySchedule) -> ScheduleChangeClassification {
        var hasStricterSignal = false

        for weekday in Weekday.allCases {
            let currentRule = current.rule(for: weekday)
            let proposedRule = proposed.rule(for: weekday)

            if !currentRule.isDayOff && proposedRule.isDayOff {
                return .weaker
            }
            if currentRule.isDayOff && !proposedRule.isDayOff {
                hasStricterSignal = true
                continue
            }
            if currentRule.isDayOff && proposedRule.isDayOff {
                continue
            }

            if proposedRule.lockMinutes > currentRule.lockMinutes {
                return .weaker
            }
            if proposedRule.lockMinutes < currentRule.lockMinutes {
                hasStricterSignal = true
            }

            if proposedRule.unlockMinutes < currentRule.unlockMinutes {
                return .weaker
            }
            if proposedRule.unlockMinutes > currentRule.unlockMinutes {
                hasStricterSignal = true
            }
        }

        return hasStricterSignal ? .stricter : .noChange
    }

    func earliestEffectiveDate(
        for change: ScheduleChangeClassification,
        requestedAt: Date
    ) -> Date {
        switch change {
        case .weaker:
            return requestedAt.addingTimeInterval(24 * 60 * 60)
        case .stricter:
            let todayStart = calendar.startOfDay(for: requestedAt)
            return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? requestedAt
        case .noChange:
            return requestedAt
        }
    }
}
