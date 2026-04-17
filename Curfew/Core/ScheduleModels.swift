import Foundation

public struct ScheduleWindow: Equatable {
    public var lockDate: Date
    public var unlockDate: Date
}

public enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    public var id: Int {
        rawValue
    }

    public var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    /// Returns the `Weekday` for the calendar day containing `date` in
    /// `calendar`. Falls back to `.monday` when the calendar component is
    /// unavailable — callers that use this for enforcement should also
    /// check `isDayOff` before trusting the result.
    public init(from date: Date, calendar: Calendar = .current) {
        let isoWeekday = calendar.component(.weekday, from: date)
        self = Weekday(rawValue: isoWeekday) ?? .monday
    }
}

public struct DayRule: Equatable, Codable {
    public var isDayOff: Bool
    public var lockMinutes: Int
    public var unlockMinutes: Int

    public static let weekdayDefault = DayRule(
        isDayOff: false,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )

    public static let weekendDefault = DayRule(
        isDayOff: true,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )

    public init(isDayOff: Bool, lockMinutes: Int, unlockMinutes: Int) {
        self.isDayOff = isDayOff
        self.lockMinutes = lockMinutes
        self.unlockMinutes = unlockMinutes
    }
}

public struct WeeklySchedule: Equatable, Codable {
    public var rules: [Weekday: DayRule]

    public init(rules: [Weekday: DayRule]) {
        self.rules = rules
    }

    public static let standardNineToFive: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { weekday in
                if weekday == .saturday || weekday == .sunday {
                    return (weekday, .weekendDefault)
                }
                return (weekday, .weekdayDefault)
            }
        )
    )

    public static let startupHours: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { weekday in
                if weekday == .saturday || weekday == .sunday {
                    return (weekday, .weekendDefault)
                }
                return (
                    weekday,
                    DayRule(
                        isDayOff: false,
                        lockMinutes: 20 * 60,
                        unlockMinutes: 8 * 60
                    )
                )
            }
        )
    )

    public static let halfDay: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { weekday in
                if weekday == .saturday || weekday == .sunday {
                    return (weekday, .weekendDefault)
                }
                return (
                    weekday,
                    DayRule(
                        isDayOff: false,
                        lockMinutes: 13 * 60,
                        unlockMinutes: 8 * 60
                    )
                )
            }
        )
    )

    public func rule(for weekday: Weekday) -> DayRule {
        rules[weekday] ?? .weekdayDefault
    }

    public func rule(for date: Date, calendar: Calendar = .current) -> DayRule {
        let weekdayInt = calendar.component(.weekday, from: date)
        guard let weekday = Weekday(rawValue: weekdayInt) else {
            return .weekdayDefault
        }
        return rule(for: weekday)
    }

    public func scheduleWindow(
        for date: Date,
        extensionMinutesGrantedToday: Int = 0,
        calendar: Calendar = .current
    ) -> ScheduleWindow? {
        let startOfDay = calendar.startOfDay(for: date)

        if let previousWindow = previousDayCarryoverWindow(
            for: date,
            startOfDay: startOfDay,
            calendar: calendar
        ) {
            return previousWindow
        }

        guard
            let currentWindow = configuredWindow(
                forDayContaining: startOfDay,
                extensionMinutes: extensionMinutesGrantedToday,
                calendar: calendar
            )
        else {
            return nil
        }

        return currentWindow
    }

    public func summarySentence(
        forNextDayFrom referenceDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        guard
            let window = configuredWindow(
                forDayContaining: tomorrow,
                extensionMinutes: 0,
                calendar: calendar
            )
        else {
            return "Tomorrow is a day off. Curfew will not enforce."
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let lockText = formatter.string(from: window.lockDate)
        let unlockText = formatter.string(from: window.unlockDate)
        return "Tomorrow, your computer locks at \(lockText) and unlocks at \(unlockText)."
    }

    private func previousDayCarryoverWindow(
        for date: Date,
        startOfDay: Date,
        calendar: Calendar
    ) -> ScheduleWindow? {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay),
              let previousWindow = configuredWindow(
                  forDayContaining: previousDay,
                  extensionMinutes: 0,
                  calendar: calendar
              ),
              previousWindow.unlockDate > startOfDay,
              date >= previousWindow.lockDate,
              date < previousWindow.unlockDate
        else {
            return nil
        }
        return previousWindow
    }

    private func configuredWindow(
        forDayContaining day: Date,
        extensionMinutes: Int,
        calendar: Calendar
    ) -> ScheduleWindow? {
        let startOfDay = calendar.startOfDay(for: day)
        let dayRule = rule(for: startOfDay, calendar: calendar)
        if dayRule.isDayOff {
            return nil
        }

        let adjustedLockMinutes = dayRule.lockMinutes + max(0, extensionMinutes)
        guard let lockDate = calendar.date(
            byAdding: .minute,
            value: adjustedLockMinutes,
            to: startOfDay
        ) else {
            return nil
        }

        let unlockBaseDay: Date = if dayRule.unlockMinutes <= adjustedLockMinutes {
            calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        } else {
            startOfDay
        }

        guard let unlockDate = calendar.date(
            byAdding: .minute,
            value: dayRule.unlockMinutes,
            to: unlockBaseDay
        ) else {
            return nil
        }

        return ScheduleWindow(lockDate: lockDate, unlockDate: unlockDate)
    }
}
