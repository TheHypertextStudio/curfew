import Foundation
import OSLog

/// The resolved lock and unlock dates for a single enforcement day.
///
/// Produced by ``WeeklySchedule/scheduleWindow(for:extensionMinutesGrantedToday:calendar:)``
/// and consumed by ``CurfewEnforcementEngine`` to determine the current phase.
/// Dates are absolute (not minutes-from-midnight) so DST transitions and
/// calendar arithmetic are handled by `Calendar` rather than by the engine.
public struct ScheduleWindow: Equatable {
    /// When the device locks today. May be after midnight if the user has a
    /// late curfew (e.g. 02:00 the next day).
    public var lockDate: Date

    /// When the device unlocks the following morning.
    public var unlockDate: Date
}

/// The seven days of the week, using ISO calendar weekday numbers as raw
/// values (Sunday = 1, Monday = 2, …, Saturday = 7).
///
/// Raw values match `Calendar.component(.weekday, from:)` so `Weekday` can
/// be round-tripped through `Calendar` without a mapping table.
public enum Weekday: Int, CaseIterable, Identifiable, Codable {
    /// ISO weekday 2.
    case monday = 2
    /// ISO weekday 3.
    case tuesday = 3
    /// ISO weekday 4.
    case wednesday = 4
    /// ISO weekday 5.
    case thursday = 5
    /// ISO weekday 6.
    case friday = 6
    /// ISO weekday 7.
    case saturday = 7
    /// ISO weekday 1 — first day of the week in `Calendar`'s default.
    case sunday = 1

    /// Satisfies `Identifiable` using the ISO weekday number. Stable across
    /// locales — `id` is never shown to the user.
    public var id: Int {
        rawValue
    }

    /// Three-letter English abbreviation used in the schedule editor grid and
    /// the reset-day picker. English only.
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
    /// check `isDayOff` before trusting the result. The fallback is logged
    /// at warning so an unexpected calendar produces traceable telemetry
    /// instead of a silent wrong rule.
    public init(from date: Date, calendar: Calendar = .current) {
        let isoWeekday = calendar.component(.weekday, from: date)
        if let value = Weekday(rawValue: isoWeekday) {
            self = value
        } else {
            Weekday.fallbackLogger.warning(
                "Weekday init falling back to .monday (iso=\(isoWeekday, privacy: .public))"
            )
            self = .monday
        }
    }

    /// Subsystem logger used for the calendar-fallback warning. Stored as
    /// a static so init() stays a pure value-returning function.
    private static let fallbackLogger = Logger(
        subsystem: "studio.hypertext.curfew",
        category: "weekday"
    )
}

// DayRule, CurfewMode, and DayRuleException live in DayRule.swift —
// extracted once mode + exception support pushed ScheduleModels past
// the file-length lint budget.

/// A seven-day curfew schedule mapping each ``Weekday`` to a ``DayRule``.
///
/// The struct is the primary domain model that users configure and that
/// ``CurfewEnforcementEngine`` evaluates. It is persisted as part of
/// ``CurfewSettings`` and synced via CloudKit.
///
/// Three built-in presets cover the most common schedules:
/// - ``standardNineToFive`` — 18:00 lock, weekends off
/// - ``startupHours`` — 20:00 lock, weekends off
/// - ``halfDay`` — 13:00 lock, weekends off
public struct WeeklySchedule: Equatable, Codable {
    /// Per-day rules keyed by weekday. Missing keys fall back to
    /// ``DayRule/weekdayDefault`` via ``rule(for:)-8b8m4``.
    public var rules: [Weekday: DayRule]

    /// Memberwise initialiser. Missing weekdays fall back to
    /// `DayRule.weekdayDefault` through `rule(for:)` at read time.
    public init(rules: [Weekday: DayRule]) {
        self.rules = rules
    }

    /// Monday–Friday: 18:00 lock, 08:00 unlock. Saturday and Sunday off.
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

    /// No automatic weekly lockout. A remote fixed-duration command remains
    /// independent of this schedule and can still be enforced by the app.
    public static let allDaysOff: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { ($0, .weekendDefault) }
        )
    )

    /// Fresh-install proposal: weekdays lock at 22:00 and unlock at 06:00;
    /// weekends remain off. Existing saved schedules are never rewritten.
    public static let tenToSix: WeeklySchedule = .init(
        rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map { weekday in
                if weekday == .saturday || weekday == .sunday {
                    return (weekday, .weekendDefault)
                }
                return (weekday, DayRule(
                    isDayOff: false,
                    lockMinutes: 22 * 60,
                    unlockMinutes: 6 * 60
                ))
            }
        )
    )

    /// Monday–Friday: 20:00 lock (start-up / longer hours), 08:00 unlock.
    /// Saturday and Sunday off.
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

    /// Monday–Friday: 13:00 lock (half-day), 08:00 unlock. Saturday and
    /// Sunday off.
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

    /// Returns the ``DayRule`` for `weekday`, falling back to
    /// ``DayRule/weekdayDefault`` when the weekday has no explicit rule.
    public func rule(for weekday: Weekday) -> DayRule {
        rules[weekday] ?? .weekdayDefault
    }

    /// Returns the ``DayRule`` for the weekday that contains `date` in
    /// `calendar`. Convenience wrapper over ``rule(for:)-8b8m4`` for call
    /// sites that work with `Date` values.
    public func rule(for date: Date, calendar: Calendar = .current) -> DayRule {
        let weekdayInt = calendar.component(.weekday, from: date)
        guard let weekday = Weekday(rawValue: weekdayInt) else {
            return .weekdayDefault
        }
        return rule(for: weekday)
    }

    /// Every saved rule in the same Monday-to-Sunday order as the editor.
    /// Use these lines when asking for consent to enable automatic lockouts:
    /// a one-day preview can hide a stricter rule later in the week.
    public var reviewLines: [String] {
        Weekday.allCases.map { weekday in
            let rule = rule(for: weekday)
            guard !rule.isDayOff else { return "\(weekday.shortName): day off" }
            let lock = minutesToHHMM(rule.lockMinutes)
            let unlock = minutesToHHMM(rule.unlockMinutes)
            let hours = rule.hoursLimitMinutes ?? 8 * 60
            let hoursText = hours.isMultiple(of: 60)
                ? "\(hours / 60) h"
                : "\(hours / 60) h \(hours % 60) m"
            let trigger = switch rule.mode {
            case .time: "locks at \(lock)"
            case .hours: "locks after \(hoursText) of work"
            case .combined: "locks at \(lock) or after \(hoursText) of work"
            }
            return "\(weekday.shortName): \(trigger); unlocks at \(unlock)"
        }
    }

    /// Returns the active ``ScheduleWindow`` for `date`, accounting for
    /// extension minutes and previous-day carryover (when the unlock time
    /// of the previous day falls after midnight into the current day).
    ///
    /// Returns `nil` when today is a day off or when calendar arithmetic
    /// fails (extremely unlikely in practice).
    ///
    /// - Parameters:
    ///   - date: The moment to evaluate — typically `Date()` from the tick loop.
    ///   - extensionMinutesGrantedToday: Minutes already granted via
    ///     extensions today; pushed onto `lockMinutes` to defer the gate.
    ///   - calendar: Calendar used for all date arithmetic. Defaults to the
    ///     device calendar so DST and timezone changes are respected.
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

    /// Returns a natural-language sentence describing tomorrow's enforcement
    /// window, e.g. "Tomorrow, work ends at 6:00 PM and resumes at 8:00 AM."
    /// Used in the schedule summary card in the primary window.
    ///
    /// Returns a day-off message when tomorrow has no enforcement window.
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
        return "Tomorrow, work ends at \(lockText) and resumes at \(unlockText)."
    }

    /// Returns the previous day's schedule window when `date` falls within
    /// its lock–unlock span (i.e. the unlock time was after midnight and we
    /// are still within that carryover window).
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

    /// Resolves the lock and unlock `Date` values for the calendar day
    /// containing `day`, applying `extensionMinutes` to the lock time.
    /// Returns `nil` when the day is marked off or calendar arithmetic fails.
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

        let extensionMinutes = max(0, extensionMinutes)
        guard !dayRule.lockMinutes.addingReportingOverflow(extensionMinutes).overflow,
              let configuredLock = configuredClock(
                  minutes: dayRule.lockMinutes, on: startOfDay, calendar: calendar
              ),
              let lockDate = calendar.date(
                  byAdding: .minute, value: extensionMinutes, to: configuredLock
              ), let unlockDate = nextUnlockClock(
                  minutes: dayRule.unlockMinutes, on: startOfDay,
                  after: lockDate, calendar: calendar
              ) else { return nil }

        return ScheduleWindow(lockDate: lockDate, unlockDate: unlockDate)
    }

    /// Preserve explicit saved day offsets, then select a later configured clock
    /// when elapsed extensions have overtaken that original unlock instant.
    private func nextUnlockClock(
        minutes: Int, on originalDay: Date, after lockDate: Date, calendar: Calendar
    ) -> Date? {
        guard let original = configuredClock(minutes: minutes, on: originalDay, calendar: calendar)
        else { return nil }
        if original > lockDate {
            return original
        }
        let offset = minutes / 1440 - (minutes % 1440 < 0 ? 1 : 0)
        let lockDay = calendar.startOfDay(for: lockDate)
        guard let base = calendar.date(byAdding: .day, value: -offset, to: lockDay),
              var candidate = configuredClock(minutes: minutes, on: base, calendar: calendar)
        else { return nil }
        if candidate <= lockDate {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: base),
                  let next = configuredClock(minutes: minutes, on: nextDay, calendar: calendar)
            else { return nil }
            candidate = next
        }
        return candidate > lockDate ? candidate : nil
    }

    /// Resolve wall-clock settings before adding elapsed extension time. Midnight
    /// plus elapsed minutes shifts post-transition clocks away from their settings.
    private func configuredClock(minutes: Int, on day: Date, calendar: Calendar) -> Date? {
        let remainder = minutes % 1440
        let dayOffset = minutes / 1440 - (remainder < 0 ? 1 : 0)
        let minuteOfDay = remainder < 0 ? remainder + 1440 : remainder
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: day) else {
            return nil
        }
        return calendar.nextDate(
            after: targetDay.addingTimeInterval(-1),
            matching: DateComponents(hour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first, direction: .forward
        )
    }
}
