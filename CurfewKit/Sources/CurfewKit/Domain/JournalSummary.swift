import Foundation

/// Arithmetic shared by every Journal aggregate so the numbers agree with the
/// Journal prototype.
public enum JournalMath {
    /// The middle value; for an even count the mean of the middle pair,
    /// rounded half toward the later value (as JavaScript's `Math.round`).
    public static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let lower = sorted[(sorted.count - 1) / 2]
        let upper = sorted[sorted.count / 2]
        return roundHalfUp(Double(lower + upper) / 2)
    }

    static func roundHalfUp(_ value: Double) -> Int {
        Int((value + 0.5).rounded(.down))
    }
}

/// Totals for a set of working days: the Journal headline, tiles and trend
/// lines read these.
///
/// Stop counts and the stop median use days with a recorded stop; the one
/// thing rate uses days with an answer; readiness uses mornings with a rating.
public struct JournalSummary: Equatable {
    /// Working days with any record.
    public let days: Int
    /// Days whose stop was recorded.
    public let daysWithStop: Int
    public let stoppedBeforeCurfew: Int
    /// Days the lock ended at curfew with no extra time.
    public let endedByLock: Int
    public let ranOver: Int
    /// Days the person called it a day themselves.
    public let calledItADay: Int
    /// Minutes past curfew across the days that ran over.
    public let extraMinutes: Int
    /// Nights that ran over.
    public let extraNights: Int
    public let oneThingAnswered: Int
    public let oneThingDone: Int
    /// Mean morning readiness on a 1 to 5 scale.
    public let readinessAverage: Double?
    /// Median signed minutes from curfew to the stop.
    public let medianStopOffsetMinutes: Int?

    public init(records: [JournalDayRecord]) {
        let offsets = records.compactMap(\.stopOffsetMinutes)
        let answers = records.compactMap(\.oneThingDone)
        let readiness = records.compactMap { $0.readiness?.fivePoint }
        self.days = records.count
        self.daysWithStop = offsets.count
        self.stoppedBeforeCurfew = offsets.count(where: { $0 < 0 })
        self.endedByLock = offsets.count(where: { $0 == 0 })
        self.ranOver = offsets.count(where: { $0 > 0 })
        self.calledItADay = records.count(where: { $0.ending?.cause == .calledItADay })
        self.extraMinutes = offsets.filter { $0 > 0 }.reduce(0, +)
        self.extraNights = ranOver
        self.oneThingAnswered = answers.count
        self.oneThingDone = answers.count(where: { $0 })
        self.readinessAverage = readiness.isEmpty
            ? nil : readiness.reduce(0, +) / Double(readiness.count)
        self.medianStopOffsetMinutes = JournalMath.median(offsets)
    }

    /// Share of recorded stops that came before curfew.
    public var stoppedBeforeCurfewRate: Double? {
        daysWithStop == 0 ? nil : Double(stoppedBeforeCurfew) / Double(daysWithStop)
    }

    /// Share of answered days the one thing was done.
    public var oneThingRate: Double? {
        oneThingAnswered == 0 ? nil : Double(oneThingDone) / Double(oneThingAnswered)
    }
}

/// The span the Journal's range control scopes everything to.
public enum JournalRange: String, CaseIterable, Sendable {
    case week
    case month
    case year

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// One week, month or year on calendar boundaries of an injected calendar.
public struct JournalPeriod: Equatable, Hashable, Sendable {
    public let range: JournalRange
    /// `[start, end)`.
    public let interval: DateInterval

    public init(range: JournalRange, interval: DateInterval) {
        self.range = range
        self.interval = interval
    }

    /// The period of `range` containing `date`. Weeks start on the calendar's
    /// `firstWeekday`.
    public static func containing(
        _ date: Date,
        range: JournalRange,
        calendar: Calendar
    ) -> JournalPeriod {
        let interval = calendar.dateInterval(of: range.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
        return JournalPeriod(range: range, interval: interval)
    }

    /// The period immediately before this one.
    public func previous(calendar: Calendar) -> JournalPeriod {
        offset(by: -1, calendar: calendar)
    }

    /// The period immediately after this one.
    public func next(calendar: Calendar) -> JournalPeriod {
        offset(by: 1, calendar: calendar)
    }

    /// The period `count` steps away; negative is earlier.
    public func offset(by count: Int, calendar: Calendar) -> JournalPeriod {
        let anchor = calendar.date(byAdding: range.component, value: count, to: interval.start)
            ?? interval.start
        return .containing(anchor, range: range, calendar: calendar)
    }

    /// Whether a record's day falls in this period.
    public func contains(day: Date) -> Bool {
        day >= interval.start && day < interval.end
    }

    /// The records whose day falls in this period, in their original order.
    public func records(from records: [JournalDayRecord]) -> [JournalDayRecord] {
        records.filter { contains(day: $0.day) }
    }

    /// The summary of the records in this period.
    public func summary(of records: [JournalDayRecord]) -> JournalSummary {
        JournalSummary(records: self.records(from: records))
    }
}
