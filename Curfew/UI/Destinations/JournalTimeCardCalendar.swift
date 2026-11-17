import CurfewKit
import Foundation

/// The calendar punches: a slot for every working day of the year, laid out
/// as week columns in two half-year bands. A hole where the evening ended
/// before curfew; a faint pilot dot otherwise. The number of holes is the
/// number of evenings out before curfew.
struct JournalTimeCardCalendar: Equatable, Sendable {
    struct Slot: Equatable, Sendable {
        let day: Date
        let band: Int
        /// The week within the band.
        let column: Int
        /// The weekday's row, in ``JournalTimeCardCalendar/weekdays`` order.
        let row: Int
        let isPunched: Bool
    }

    /// A month's name over the column where its first slot falls.
    struct MonthLabel: Equatable, Sendable {
        let name: String
        let band: Int
        let column: Int
    }

    /// The rows top to bottom, in the person's week order: the working
    /// weekdays plus any weekday that has a record.
    let weekdays: [Weekday]
    let columnsPerBand: Int
    let slots: [Slot]
    let months: [MonthLabel]

    var holeCount: Int {
        slots.count(where: \.isPunched)
    }

    init(
        year: Int,
        records: [JournalDayRecord],
        workingWeekdays: Set<Weekday>,
        format: JournalFormat
    ) {
        let calendar = format.calendar
        let early = Set(records.filter { $0.outcome == .stoppedBeforeCurfew }
            .map { calendar.startOfDay(for: $0.day) })
        let recorded = Set(records.map { Weekday(from: $0.day, calendar: calendar) })
        let order = (0 ..< 7)
            .compactMap { Weekday(rawValue: (calendar.firstWeekday - 1 + $0) % 7 + 1) }
        let rows = order.filter { workingWeekdays.contains($0) || recorded.contains($0) }
        self.weekdays = rows

        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start
        else {
            self.columnsPerBand = 0
            self.slots = []
            self.months = []
            return
        }
        let days = Self.days(
            from: start,
            to: end,
            firstWeek: firstWeek,
            rows: rows,
            calendar: calendar
        )
        // The second band starts with the week July begins in, so each
        // band opens on its half-year's first month.
        let weeks = (days.map(\.week).max() ?? 0) + 1
        let july = calendar.date(from: DateComponents(year: year, month: 7, day: 1))
            .map { calendar.dateComponents([.day], from: firstWeek, to: $0).day ?? 0 }
            .map { $0 / 7 } ?? weeks / 2
        self.columnsPerBand = max(july, weeks - july)
        self.slots = days.map { entry in
            let band = entry.week < july ? 0 : 1
            return Slot(
                day: entry.day,
                band: band,
                column: entry.week - band * july,
                row: entry.row,
                isPunched: early.contains(entry.day)
            )
        }
        self.months = Self.monthLabels(slots, format: format)
    }

    /// One working day's place: its week from the first week of the year,
    /// and its row.
    private struct Place {
        let day: Date
        let week: Int
        let row: Int
    }

    private static func days(
        from start: Date, to end: Date, firstWeek: Date, rows: [Weekday], calendar: Calendar
    ) -> [Place] {
        var places: [Place] = []
        var day = start
        while day < end {
            if let row = rows.firstIndex(of: Weekday(from: day, calendar: calendar)) {
                let offset = calendar.dateComponents([.day], from: firstWeek, to: day).day ?? 0
                places.append(Place(day: day, week: offset / 7, row: row))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return places
    }

    /// Each month's name over the column of its first slot.
    private static func monthLabels(_ slots: [Slot], format: JournalFormat) -> [MonthLabel] {
        var months: [MonthLabel] = []
        var seen: Set<Int> = []
        for slot in slots
            where seen.insert(format.calendar.component(.month, from: slot.day)).inserted {
            months.append(MonthLabel(
                name: format.monthShort(slot.day),
                band: slot.band,
                column: slot.column
            ))
        }
        return months
    }
}
