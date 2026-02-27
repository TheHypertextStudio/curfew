import Foundation

struct ScheduleWindow: Equatable, Sendable {
    var lockDate: Date
    var unlockDate: Date
}

enum Weekday: Int, CaseIterable, Identifiable, Codable, Sendable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var shortName: String {
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
}

struct DayRule: Equatable, Codable, Sendable {
    var isDayOff: Bool
    var lockMinutes: Int
    var unlockMinutes: Int

    static let weekdayDefault = DayRule(
        isDayOff: false,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )

    static let weekendDefault = DayRule(
        isDayOff: true,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )
}

struct WeeklySchedule: Equatable, Codable, Sendable {
    var rules: [Weekday: DayRule]

    static let standardNineToFive: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { weekday in
                if weekday == .saturday || weekday == .sunday {
                    return (weekday, .weekendDefault)
                }
                return (weekday, .weekdayDefault)
            }
        )
    )

    static let startupHours: WeeklySchedule = .init(
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

    static let halfDay: WeeklySchedule = .init(
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

    func rule(for weekday: Weekday) -> DayRule {
        rules[weekday] ?? .weekdayDefault
    }

    func rule(for date: Date, calendar: Calendar = .current) -> DayRule {
        let weekdayInt = calendar.component(.weekday, from: date)
        guard let weekday = Weekday(rawValue: weekdayInt) else {
            return .weekdayDefault
        }
        return rule(for: weekday)
    }

    func scheduleWindow(
        for date: Date,
        extensionMinutesGrantedToday: Int = 0,
        calendar: Calendar = .current
    ) -> ScheduleWindow? {
        let startOfDay = calendar.startOfDay(for: date)

        if
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startOfDay),
            let previousWindow = configuredWindow(
                forDayContaining: previousDay,
                extensionMinutes: 0,
                calendar: calendar
            ),
            previousWindow.unlockDate > startOfDay,
            date >= previousWindow.lockDate,
            date < previousWindow.unlockDate
        {
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

    func summarySentence(
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
        guard let lockDate = calendar.date(byAdding: .minute, value: adjustedLockMinutes, to: startOfDay) else {
            return nil
        }

        let unlockBaseDay: Date
        if dayRule.unlockMinutes <= adjustedLockMinutes {
            unlockBaseDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        } else {
            unlockBaseDay = startOfDay
        }

        guard let unlockDate = calendar.date(byAdding: .minute, value: dayRule.unlockMinutes, to: unlockBaseDay) else {
            return nil
        }

        return ScheduleWindow(lockDate: lockDate, unlockDate: unlockDate)
    }
}
