import Foundation

/// Why a pattern has nothing to report yet.
public enum JournalPatternShortfall: Equatable, Sendable {
    /// No days to read.
    case noDays
    /// Only one kind of day, so there is nothing to compare against.
    case nothingToCompare
    /// Too few days of the kind the pattern needs.
    case tooFewDays(have: Int, need: Int)
    /// The gap is below the threshold: minutes for the weekday pattern,
    /// percentage points for the readiness pattern.
    case gapTooSmall(have: Int, need: Int)
}

/// A pattern either earned with its finding, or not earned with the reason.
public enum JournalPatternVerdict<Finding: Equatable>: Equatable {
    case earned(Finding)
    case notEarned(JournalPatternShortfall)

    public var isEarned: Bool {
        if case .earned = self {
            return true
        }
        return false
    }
}

/// "Fridays run about 30m later than your other days."
public struct WeekdayFinding: Equatable {
    public let weekday: Weekday
    /// That weekday's median stop minus the median of every other day.
    public let minutesLater: Int
    /// How many of that weekday the finding rests on.
    public let days: Int
}

/// Typical stop by weekday plus whether one weekday stands out.
public struct WeekdayPattern: Equatable {
    /// Median signed stop minutes by weekday, for weekdays with a stop.
    public let medians: [Weekday: Int]
    /// Days with a stop by weekday.
    public let counts: [Weekday: Int]
    public let verdict: JournalPatternVerdict<WeekdayFinding>
}

/// "You did the one thing on 80% of mornings you felt ready, and 40% of the rest."
public struct ReadinessFinding: Equatable, Sendable {
    public let readyRate: Double
    public let otherRate: Double
    public let readyMornings: Int
    public let otherMornings: Int
}

/// The one thing against morning readiness.
public struct ReadinessPattern: Equatable {
    /// Mornings rated 4 or 5 of 5 with a one thing answer.
    public let readyMornings: Int
    /// Mornings rated 3 or lower with a one thing answer.
    public let otherMornings: Int
    public let readyRate: Double?
    public let otherRate: Double?
    public let verdict: JournalPatternVerdict<ReadinessFinding>
}

/// "You ended 12 days yourself. The lock ended 6. 3 ran over."
public struct DayEndingsFinding: Equatable, Sendable {
    public let stoppedBeforeCurfew: Int
    public let endedByLock: Int
    public let ranOver: Int
    /// Days with a recorded stop.
    public let days: Int

    public init(stoppedBeforeCurfew: Int, endedByLock: Int, ranOver: Int, days: Int) {
        self.stoppedBeforeCurfew = stoppedBeforeCurfew
        self.endedByLock = endedByLock
        self.ranOver = ranOver
        self.days = days
    }
}

/// The three-way split of how days ended.
public struct DayEndingsPattern: Equatable {
    public let verdict: JournalPatternVerdict<DayEndingsFinding>
}

/// The Journal's observations. Each one is shown only with enough days behind
/// it and a clear gap; otherwise it reports why not.
public enum JournalPatterns {
    public static let weekdayMinimumDays = 4
    public static let weekdayMinimumGapMinutes = 10
    public static let readinessMinimumMornings = 5
    public static let readinessMinimumGapPoints = 12
    /// Week and month ranges read the twelve weeks to the period's end.
    public static let windowDays = 84

    /// The span the patterns read for `period`: the whole year in year range,
    /// otherwise the twelve weeks ending where the period ends.
    public static func window(for period: JournalPeriod, calendar: Calendar) -> DateInterval {
        guard period.range != .year else { return period.interval }
        let start = calendar.date(byAdding: .day, value: -windowDays, to: period.interval.end)
            ?? period.interval.start
        return DateInterval(start: start, end: period.interval.end)
    }

    /// The weekday whose median stop is latest, earned when it has at least
    /// four days and runs at least ten minutes later than the median of every
    /// other day.
    public static func weekday(
        _ records: [JournalDayRecord],
        calendar: Calendar
    ) -> WeekdayPattern {
        var offsetsByWeekday: [Weekday: [Int]] = [:]
        for record in records {
            guard let offset = record.stopOffsetMinutes,
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: record.day))
            else { continue }
            offsetsByWeekday[weekday, default: []].append(offset)
        }
        let medians = offsetsByWeekday.compactMapValues(JournalMath.median)
        let counts = offsetsByWeekday.mapValues(\.count)

        var latest: Weekday?
        for weekday in Weekday.allCases {
            guard let median = medians[weekday] else { continue }
            if let current = latest, let currentMedian = medians[current], median <= currentMedian {
                continue
            }
            latest = weekday
        }

        let verdict: JournalPatternVerdict<WeekdayFinding>
        if let latest, let latestMedian = medians[latest] {
            let others = offsetsByWeekday.filter { $0.key != latest }.values.flatMap(\.self)
            let days = counts[latest] ?? 0
            if let othersMedian = JournalMath.median(others) {
                let gap = latestMedian - othersMedian
                if days < weekdayMinimumDays {
                    verdict = .notEarned(.tooFewDays(have: days, need: weekdayMinimumDays))
                } else if gap < weekdayMinimumGapMinutes {
                    verdict = .notEarned(.gapTooSmall(have: gap, need: weekdayMinimumGapMinutes))
                } else {
                    verdict = .earned(WeekdayFinding(
                        weekday: latest,
                        minutesLater: gap,
                        days: days
                    ))
                }
            } else {
                verdict = .notEarned(.nothingToCompare)
            }
        } else {
            verdict = .notEarned(.noDays)
        }
        return WeekdayPattern(medians: medians, counts: counts, verdict: verdict)
    }

    /// The one thing done rate on mornings rated 4 or more of 5 against the
    /// rest, earned with five mornings of each kind and a twelve-point gap.
    public static func readiness(_ records: [JournalDayRecord]) -> ReadinessPattern {
        var ready: [Bool] = []
        var other: [Bool] = []
        for record in records {
            guard let rating = record.readiness, let done = record.oneThingDone else { continue }
            if rating.fivePoint >= 4 {
                ready.append(done)
            } else {
                other.append(done)
            }
        }
        let readyRate = rate(ready)
        let otherRate = rate(other)

        let verdict: JournalPatternVerdict<ReadinessFinding>
        if ready.isEmpty, other.isEmpty {
            verdict = .notEarned(.noDays)
        } else if min(ready.count, other.count) < readinessMinimumMornings {
            verdict = .notEarned(.tooFewDays(
                have: min(ready.count, other.count), need: readinessMinimumMornings
            ))
        } else if let readyRate, let otherRate {
            let gap = abs(readyRate - otherRate)
            if gap + 1e-9 < Double(readinessMinimumGapPoints) / 100 {
                verdict = .notEarned(.gapTooSmall(
                    have: Int((gap * 100).rounded()), need: readinessMinimumGapPoints
                ))
            } else {
                verdict = .earned(ReadinessFinding(
                    readyRate: readyRate, otherRate: otherRate,
                    readyMornings: ready.count, otherMornings: other.count
                ))
            }
        } else {
            verdict = .notEarned(.nothingToCompare)
        }
        return ReadinessPattern(
            readyMornings: ready.count, otherMornings: other.count,
            readyRate: readyRate, otherRate: otherRate, verdict: verdict
        )
    }

    /// How days ended: before curfew, by the lock at curfew, or over.
    public static func dayEndings(_ records: [JournalDayRecord]) -> DayEndingsPattern {
        let summary = JournalSummary(records: records)
        guard summary.daysWithStop > 0
        else { return DayEndingsPattern(verdict: .notEarned(.noDays)) }
        return DayEndingsPattern(verdict: .earned(DayEndingsFinding(
            stoppedBeforeCurfew: summary.stoppedBeforeCurfew,
            endedByLock: summary.endedByLock,
            ranOver: summary.ranOver,
            days: summary.daysWithStop
        )))
    }

    private static func rate(_ answers: [Bool]) -> Double? {
        answers.isEmpty ? nil : Double(answers.count(where: { $0 })) / Double(answers.count)
    }
}

/// A value the Journal tiles trend over prior periods.
public enum JournalMetric: CaseIterable, Sendable {
    case stoppedBeforeCurfewRate
    case oneThingRate
    case extraMinutes
    case readinessAverage
    case medianStopOffset

    /// The metric's value in `summary`, or `nil` when the summary cannot say.
    public func value(in summary: JournalSummary) -> Double? {
        switch self {
        case .stoppedBeforeCurfewRate: summary.stoppedBeforeCurfewRate
        case .oneThingRate: summary.oneThingRate
        case .extraMinutes: summary.days == 0 ? nil : Double(summary.extraMinutes)
        case .readinessAverage: summary.readinessAverage
        case .medianStopOffset: summary.medianStopOffsetMinutes.map(Double.init)
        }
    }
}

/// One point on a tile's trend line.
public struct JournalTrendPoint: Equatable {
    public let period: JournalPeriod
    public let value: Double
}

/// Trailing series for the tiles' trend lines.
public enum JournalTrend {
    /// The metric over prior periods, oldest first, ending with `period`.
    /// Week range: the twelve weeks to `period`. Month range: the twelve months
    /// to `period`. Year range: each month of that year. Periods without a
    /// value are skipped, as in the prototype.
    public static func points(
        _ metric: JournalMetric,
        endingAt period: JournalPeriod,
        records: [JournalDayRecord],
        calendar: Calendar,
        count: Int = 12
    ) -> [JournalTrendPoint] {
        let periods: [JournalPeriod]
        switch period.range {
        case .week, .month:
            periods = (0 ..< count).reversed().map { period.offset(by: -$0, calendar: calendar) }
        case .year:
            let first = JournalPeriod.containing(
                period.interval.start,
                range: .month,
                calendar: calendar
            )
            periods = (0 ..< 12).map { first.offset(by: $0, calendar: calendar) }
                .filter { $0.interval.start < period.interval.end }
        }
        return periods.compactMap { candidate in
            let summary = candidate.summary(of: records)
            guard summary.days > 0, let value = metric.value(in: summary) else { return nil }
            return JournalTrendPoint(period: candidate, value: value)
        }
    }
}

/// The four totals on the year in review card, and the year's headline.
public struct JournalYearInReview: Equatable {
    public let days: Int
    public let daysStoppedBeforeCurfew: Int
    public let medianStopOffsetMinutes: Int?
    /// Median stop as minutes after the working day's midnight on the wall
    /// clock; past midnight counts beyond 1440.
    public let typicalStopMinuteOfDay: Int?
    public let oneThingDays: Int
    /// Minutes past curfew across the year.
    public let extraMinutes: Int
    /// Most consecutive working days stopped before curfew. A day with an
    /// unknown stop breaks the run; days off have no record and do not.
    public let longestRunBeforeCurfew: Int

    /// Builds the totals from `records`, usually one year's records.
    public init(records: [JournalDayRecord], calendar: Calendar) {
        let sorted = records.sorted { $0.day < $1.day }
        let summary = JournalSummary(records: sorted)
        self.days = summary.days
        self.daysStoppedBeforeCurfew = summary.stoppedBeforeCurfew
        self.medianStopOffsetMinutes = summary.medianStopOffsetMinutes
        self.oneThingDays = summary.oneThingDone
        self.extraMinutes = summary.extraMinutes

        var run = 0
        var best = 0
        for record in sorted {
            if record.outcome == .stoppedBeforeCurfew {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        self.longestRunBeforeCurfew = best

        self.typicalStopMinuteOfDay = JournalMath.median(sorted.compactMap { record in
            guard let stoppedAt = record.stoppedAt else { return nil }
            let clock = calendar.dateComponents([.hour, .minute], from: stoppedAt)
            let dayShift = calendar.dateComponents(
                [.day], from: record.day, to: calendar.startOfDay(for: stoppedAt)
            ).day ?? 0
            return dayShift * 1440 + (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        })
    }
}
