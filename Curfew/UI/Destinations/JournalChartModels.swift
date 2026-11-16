import CurfewKit
import Foundation

/// The vertical scale of the "When you stopped" chart, in minutes where
/// positive is early (up) and negative is over (down). Rounded to half hours
/// as in the prototype, with at least an hour of headroom above curfew and
/// half an hour below it.
struct JournalChartScale: Equatable {
    let top: Int
    let bottom: Int
    let step: Int

    /// - Parameter offsets: signed stop minutes, negative before curfew.
    init(offsets: [Int]) {
        let earliest = (offsets + [-60]).min() ?? -60
        let latest = (offsets + [0]).max() ?? 0
        let top = Int((Double(-earliest + 12) / 30).rounded(.up)) * 30
        let bottom = latest > 0 ? -Int((Double(latest + 16) / 30).rounded(.up)) * 30 : -30
        self.top = top
        self.bottom = bottom
        self.step = top - bottom > 150 ? 60 : 30
    }

    /// Gridline values from the top down, including curfew.
    var ticks: [Int] {
        let first = top / step * step
        return Array(stride(from: first, through: bottom, by: -step))
    }

    /// 0 at the top of the plot, 1 at the bottom, for a value in minutes
    /// early (positive) or over (negative).
    func position(_ value: Int) -> Double {
        Double(top - value) / Double(max(1, top - bottom))
    }
}

/// The year grid's seven-step colour scale, plus days with no stop time.
enum JournalHeatBin: CaseIterable, Equatable {
    case early3
    case early2
    case early1
    case atCurfew
    case over1
    case over2
    case over3
    case noRecord

    /// - Parameter offset: signed stop minutes, negative before curfew.
    init(offset: Int?) {
        guard let offset else {
            self = .noRecord
            return
        }
        switch offset {
        case ...(-45): self = .early3
        case ...(-15): self = .early2
        case ..<0: self = .early1
        case 0: self = .atCurfew
        case ...15: self = .over1
        case ...30: self = .over2
        default: self = .over3
        }
    }

    /// The steps the legend shows, earliest first.
    static let scale: [JournalHeatBin] = [
        .early3, .early2, .early1, .atCurfew, .over1, .over2, .over3
    ]
}

/// Which side of curfew a day landed on; it picks the mark colour.
enum JournalMark: Equatable {
    case early
    case atCurfew
    case over

    init(offset: Int) {
        self = offset < 0 ? .early : offset > 0 ? .over : .atCurfew
    }
}

/// The hover and focus card for one day.
struct JournalTooltip: Equatable {
    let date: String
    let headline: String
    let mark: JournalMark?
    let markText: String?
    let lines: [String]
    let footnote: String?
}

/// One working day in the shown period: a column in the chart, a cell in
/// the year grid.
struct JournalDay: Identifiable, Equatable {
    enum Kind: Equatable {
        /// The stop time is known.
        case stopped
        /// The day has a record but no stop time, as before this release.
        case noStopTime
        /// A working day with nothing recorded at all.
        case nothingRecorded
    }

    let day: Date
    let kind: Kind
    let record: JournalDayRecord?
    /// Signed stop minutes, negative before curfew.
    let offset: Int?
    /// The first day shown from its calendar week; month range leaves a gap
    /// before it.
    let startsWeek: Bool
    let axisLabel: String
    /// The stop time, only on the period's earliest and latest days.
    let extremeLabel: String?
    let accessibilityLabel: String
    let tooltip: JournalTooltip

    var id: Date {
        day
    }

    var heatBin: JournalHeatBin {
        JournalHeatBin(offset: offset)
    }

    var mark: JournalMark? {
        offset.map(JournalMark.init(offset:))
    }
}

/// Where each day sits in the year grid: one column per calendar week, one
/// row per weekday.
struct JournalYearGrid: Equatable {
    struct Row: Equatable {
        let weekday: Weekday
        let label: String
        /// Only every other row is labelled, as in the prototype.
        let showsLabel: Bool
    }

    struct Cell: Equatable {
        let dayIndex: Int
        let column: Int
        let row: Int
    }

    struct MonthLabel: Equatable {
        let label: String
        let column: Int
    }

    let rows: [Row]
    let columns: Int
    let cells: [Cell]
    let months: [MonthLabel]

    init(
        days: [JournalDay],
        period: JournalPeriod,
        workingWeekdays: Set<Weekday>,
        format: JournalFormat
    ) {
        let calendar = format.calendar
        let ordered = (0 ..< 7).compactMap { offset in
            Weekday(rawValue: (calendar.firstWeekday - 1 + offset) % 7 + 1)
        }
        let present = Set(days.compactMap { day in
            Weekday(rawValue: calendar.component(.weekday, from: day.day))
        })
        let weekdays = ordered.filter { workingWeekdays.contains($0) || present.contains($0) }
        var workingIndex = 0
        self.rows = weekdays.map { weekday in
            let isWorking = workingWeekdays.contains(weekday)
            defer {
                if isWorking {
                    workingIndex += 1
                }
            }
            return Row(
                weekday: weekday,
                label: format.weekdayShort(weekday),
                showsLabel: isWorking && workingIndex % 2 == 0
            )
        }
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: period.interval.start)?
            .start ?? period.interval.start
        func column(_ date: Date) -> Int {
            let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return (calendar.dateComponents([.day], from: firstWeek, to: week).day ?? 0) / 7
        }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: period.interval.end)
            ?? period.interval.end
        self.columns = column(lastDay) + 1
        self.cells = days.enumerated().compactMap { index, day in
            guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: day.day)),
                  let row = weekdays.firstIndex(of: weekday)
            else { return nil }
            return Cell(dayIndex: index, column: column(day.day), row: row)
        }
        var months: [MonthLabel] = []
        var seen = Set<Int>()
        for day in days {
            let month = calendar.component(.month, from: day.day)
            guard seen.insert(month).inserted else { continue }
            months.append(MonthLabel(label: format.monthShort(day.day), column: column(day.day)))
        }
        self.months = months
    }
}
