import CurfewKit
import Foundation

/// Locale-aware wording for the Journal: durations, clock times, days,
/// period names and the curfew-relative phrases the prototype uses.
///
/// Times always come from the locale's formatter, never a fixed 24-hour
/// string. Durations use the compact "1h 15m" form the prototype uses.
struct JournalFormat {
    let calendar: Calendar
    let locale: Locale

    init(calendar: Calendar = .current, locale: Locale = .current) {
        var calendar = calendar
        calendar.locale = locale
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: - Numbers

    /// "45m", "1h", "1h 15m". The sign is dropped; callers say early or over.
    func duration(_ minutes: Int) -> String {
        let total = abs(minutes)
        let hours = total / 60
        let rest = total % 60
        guard hours > 0 else { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// A share as a whole percentage, rounded half up like the prototype.
    func percent(_ rate: Double) -> String {
        "\(JournalFormat.roundHalfUp(rate * 100))%"
    }

    /// One decimal place, for the readiness average.
    func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// "1 day", "3 days".
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : plural ?? singular + "s")"
    }

    static func roundHalfUp(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }

    // MARK: - Curfew-relative phrases

    /// "18m before curfew", "45m over", "at curfew".
    func relative(_ offset: Int) -> String {
        offset < 0 ? "\(duration(offset)) before curfew"
            : offset > 0 ? "\(duration(offset)) over" : "at curfew"
    }

    /// "18m early", "45m over", "At curfew".
    func relativeShort(_ offset: Int) -> String {
        offset < 0 ? "\(duration(offset)) early"
            : offset > 0 ? "\(duration(offset)) over" : "At curfew"
    }

    /// A chart tick, where positive values are minutes early.
    func tickLabel(_ value: Int) -> String {
        value == 0 ? "Curfew" : value > 0 ? "\(duration(value)) early" : "\(duration(value)) over"
    }

    // MARK: - Dates

    private func style() -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// The locale's short time, "5:42 PM".
    func clock(_ date: Date) -> String {
        Date.FormatStyle(
            date: .omitted, time: .shortened,
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        )
        .format(date)
        .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "Tue, Nov 10".
    func shortDay(_ date: Date) -> String {
        style().weekday(.abbreviated).month(.abbreviated).day().format(date)
    }

    /// "Nov 9".
    func monthDay(_ date: Date) -> String {
        style().month(.abbreviated).day().format(date)
    }

    /// "9".
    func dayNumber(_ date: Date) -> String {
        style().day().format(date)
    }

    /// "Mon".
    func weekdayShort(_ date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        return calendar.shortStandaloneWeekdaySymbols[index]
    }

    /// "Mon", for a weekday rather than a date.
    func weekdayShort(_ weekday: Weekday) -> String {
        calendar.shortStandaloneWeekdaySymbols[weekday.rawValue - 1]
    }

    /// "Tuesdays".
    func weekdayPlural(_ weekday: Weekday) -> String {
        calendar.standaloneWeekdaySymbols[weekday.rawValue - 1] + "s"
    }

    /// "Mar", for the year grid's month labels.
    func monthShort(_ date: Date) -> String {
        style().month(.abbreviated).format(date)
    }

    // MARK: - Periods

    /// "Nov 9 to 13", "Nov 30 to Dec 4", "October 2026", "2026". A week is
    /// labelled by its first and last working days.
    func periodLabel(
        _ period: JournalPeriod,
        workingWeekdays: Set<Weekday>,
        recordedDays: [Date] = []
    ) -> String {
        switch period.range {
        case .week:
            let days = (0 ..< 7).compactMap {
                calendar.date(byAdding: .day, value: $0, to: period.interval.start)
            }
            let recorded = Set(recordedDays.map { calendar.startOfDay(for: $0) })
            let working = days.filter { day in
                recorded.contains(calendar.startOfDay(for: day))
                    || Weekday(rawValue: calendar.component(.weekday, from: day))
                    .map(workingWeekdays.contains) ?? false
            }
            let first = working.first ?? days.first ?? period.interval.start
            let last = working.last ?? days.last ?? period.interval.start
            let sameMonth = calendar.component(.month, from: first)
                == calendar.component(.month, from: last)
            return "\(monthDay(first)) to \(sameMonth ? dayNumber(last) : monthDay(last))"
        case .month:
            return style().month(.wide).year().format(period.interval.start)
        case .year:
            return style().year().format(period.interval.start)
        }
    }

    /// How the comparison sentence names the previous period: "the week
    /// before", "September". Year range has no comparison.
    func previousName(_ period: JournalPeriod) -> String? {
        switch period.range {
        case .week:
            "the week before"
        case .month:
            style().month(.wide).format(period.previous(calendar: calendar).interval.start)
        case .year:
            nil
        }
    }

    /// "this week", for sentences about the shown period.
    static func periodNoun(_ range: JournalRange) -> String {
        switch range {
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
    }

    /// The last day a period covers that has happened, "Nov 13".
    func lastDayLabel(_ period: JournalPeriod, today: Date) -> String {
        let end = calendar.date(byAdding: .day, value: -1, to: period.interval.end)
            ?? period.interval.end
        return monthDay(min(end, calendar.startOfDay(for: today)))
    }
}

/// Sentences about how days ended. A clause whose count is zero is left
/// out, "all" is said plainly, and when no day ended early the sentence
/// leads with what did happen.
enum JournalCountWords {
    /// "You stopped before curfew on 3 of 5 days. The lock ended 2."
    static func headline(early: Int, lock: Int, over: Int) -> String {
        let total = early + lock + over
        guard early > 0 else { return withoutEarly(lock: lock, over: over) }
        if early == total {
            return total == 1 ? "You stopped before curfew on your one day."
                : "You stopped before curfew on all \(total) days."
        }
        let lead = "You stopped before curfew on \(early) of "
            + "\(JournalFormat.count(total, "day"))."
        return ([lead] + rest(lock: lock, over: over)).joined(separator: " ")
    }

    /// "You ended 12 days yourself. The lock ended 6. 3 ran over."
    static func endings(early: Int, lock: Int, over: Int) -> String {
        guard early > 0 else { return withoutEarly(lock: lock, over: over) }
        let lead = "You ended \(JournalFormat.count(early, "day")) yourself."
        return ([lead] + rest(lock: lock, over: over)).joined(separator: " ")
    }

    private static func rest(lock: Int, over: Int) -> [String] {
        [lock > 0 ? "The lock ended \(lock)." : nil, over > 0 ? "\(over) ran over." : nil]
            .compactMap(\.self)
    }

    private static func withoutEarly(lock: Int, over: Int) -> String {
        let total = lock + over
        if over == 0 {
            return total == 1 ? "The lock ended your one day." : "The lock ended all \(total) days."
        }
        if lock == 0 {
            return total == 1 ? "Your one day ran over." : "All \(total) days ran over."
        }
        return "The lock ended \(JournalFormat.count(lock, "day")) and \(over) ran over."
    }
}
