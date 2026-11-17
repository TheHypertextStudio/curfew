import Foundation

/// Locale-aware review text for the weekly schedule, used when asking the
/// person to turn the schedule on and by the command line and assistants.
public extension WeeklySchedule {
    /// ``reviewLines`` with times written in `locale`'s clock format, for
    /// example "Mon, 5:00 PM to 8:00 AM" or "Sat, day off".
    func reviewLines(locale: Locale) -> [String] {
        Weekday.allCases.map { weekday in
            let rule = rule(for: weekday)
            guard !rule.isDayOff else { return "\(weekday.shortName), day off" }
            let lock = Self.clockText(minutes: rule.lockMinutes, locale: locale)
            let unlock = Self.clockText(minutes: rule.unlockMinutes, locale: locale)
            let limit = rule.hoursLimitMinutes ?? 8 * 60
            let hours = Self.durationText(minutes: limit, locale: locale)
            return switch rule.mode {
            case .time: "\(weekday.shortName), \(lock) to \(unlock)"
            case .hours: "\(weekday.shortName), after \(hours) of work, to \(unlock)"
            case .combined:
                "\(weekday.shortName), \(lock) or after \(hours) of work, to \(unlock)"
            }
        }
    }

    /// Minutes after midnight as a wall-clock time in `locale`'s format.
    internal static func clockText(minutes: Int, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
            .string(from: Date(timeIntervalSinceReferenceDate: TimeInterval(minutes * 60)))
    }

    /// A work-hours limit such as "8 hours" or "7 hours 30 minutes".
    internal static func durationText(minutes: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute]
        let text = formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes / 60) hours"
        return text.replacingOccurrences(of: ", ", with: " ")
    }
}
