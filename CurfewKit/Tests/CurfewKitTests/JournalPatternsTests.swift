@testable import CurfewKit
import Foundation
import Testing

private typealias F = JournalFixture

/// Monday, November 2, 2026, the start of the hand-built weeks below.
private let firstMonday = F.date(2026, 11, 2)

/// One record per weekday for `weeks` weeks. `offset` chooses each day's
/// stop from its weekday (2 = Monday … 6 = Friday) and week index.
private func weeks(
    _ count: Int,
    offset: (_ weekday: Int, _ week: Int) -> Int?
) -> [JournalDayRecord] {
    let calendar = F.utc
    var records: [JournalDayRecord] = []
    for week in 0 ..< count {
        for weekday in 2 ... 6 {
            let day = calendar.date(byAdding: .day, value: week * 7 + weekday - 2, to: firstMonday)!
            guard let value = offset(weekday, week) else { continue }
            records.append(F.record(day, offset: value))
        }
    }
    return records
}

struct WeekdayPatternTests {
    @Test("A weekday with four days and a ten-minute later median is earned")
    func earned() {
        let records = weeks(4) { weekday, _ in weekday == 6 ? 20 : -10 }
        let pattern = JournalPatterns.weekday(records, calendar: F.utc)
        guard case .earned(let finding) = pattern.verdict else {
            Issue.record("expected an earned weekday pattern, got \(pattern.verdict)")
            return
        }
        #expect(finding.weekday == .friday)
        #expect(finding.minutesLater == 30)
        #expect(finding.days == 4)
        #expect(pattern.medians[.friday] == 20)
        #expect(pattern.medians[.monday] == -10)
        #expect(pattern.counts[.friday] == 4)
    }

    @Test("A gap of exactly ten minutes is earned; nine is not")
    func gapThreshold() {
        let ten = JournalPatterns.weekday(
            weeks(4) { weekday, _ in weekday == 6 ? 10 : 0 },
            calendar: F.utc
        )
        #expect(ten.verdict.isEarned)
        let nine = JournalPatterns.weekday(
            weeks(4) { weekday, _ in weekday == 6 ? 9 : 0 },
            calendar: F.utc
        )
        #expect(nine.verdict == .notEarned(.gapTooSmall(have: 9, need: 10)))
    }

    @Test("Three of the latest weekday is not enough")
    func tooFewDays() {
        let records = weeks(4) { weekday, week in
            weekday == 6 ? (week == 0 ? nil : 30) : 0
        }
        let pattern = JournalPatterns.weekday(records, calendar: F.utc)
        #expect(pattern.verdict == .notEarned(.tooFewDays(have: 3, need: 4)))
    }

    @Test("No days, or only one weekday, has nothing to report")
    func nothingToReport() {
        #expect(JournalPatterns.weekday([], calendar: F.utc).verdict == .notEarned(.noDays))
        let fridays = weeks(5) { weekday, _ in weekday == 6 ? 30 : nil }
        #expect(
            JournalPatterns.weekday(fridays, calendar: F.utc).verdict
                == .notEarned(.nothingToCompare)
        )
    }

    @Test("Days with an unknown stop are left out of the weekday pattern")
    func ignoresUnknownStops() {
        var records = weeks(4) { weekday, _ in weekday == 6 ? 20 : 0 }
        records.append(F.record(F.date(2026, 12, 4), offset: nil))
        let pattern = JournalPatterns.weekday(records, calendar: F.utc)
        #expect(pattern.counts[.friday] == 4)
    }
}

struct ReadinessPatternTests {
    private func mornings(ready: [Bool], other: [Bool]) -> [JournalDayRecord] {
        let days = F.days(from: firstMonday, count: ready.count + other.count)
        return ready.enumerated().map { index, done in
            F.record(days[index], offset: 0, done: done, ready: 4 + index % 2)
        } + other.enumerated().map { index, done in
            F.record(days[ready.count + index], offset: 0, done: done, ready: 1 + index % 3)
        }
    }

    @Test("Five mornings of each kind and a twelve-point gap is earned")
    func earned() {
        let records = mornings(
            ready: [true, true, true, true, false],
            other: [true, true, false, false, false]
        )
        let pattern = JournalPatterns.readiness(records)
        guard case .earned(let finding) = pattern.verdict else {
            Issue.record("expected an earned readiness pattern, got \(pattern.verdict)")
            return
        }
        #expect(finding.readyRate == 0.8)
        #expect(finding.otherRate == 0.4)
        #expect(finding.readyMornings == 5)
        #expect(finding.otherMornings == 5)
    }

    @Test("Four ready mornings is not enough")
    func tooFew() {
        let pattern = JournalPatterns.readiness(mornings(
            ready: [true, true, true, true],
            other: [false, false, false, false, false]
        ))
        #expect(pattern.verdict == .notEarned(.tooFewDays(have: 4, need: 5)))
    }

    @Test("A gap of exactly twelve points is earned; ten is not")
    func gapThreshold() {
        let twelve = mornings(
            ready: Array(repeating: true, count: 13) + Array(repeating: false, count: 12),
            other: Array(repeating: true, count: 10) + Array(repeating: false, count: 15)
        )
        #expect(JournalPatterns.readiness(twelve).verdict.isEarned)
        let ten = mornings(
            ready: Array(repeating: true, count: 6) + Array(repeating: false, count: 4),
            other: Array(repeating: true, count: 5) + Array(repeating: false, count: 5)
        )
        #expect(
            JournalPatterns.readiness(ten).verdict == .notEarned(.gapTooSmall(have: 10, need: 12))
        )
    }

    @Test("Mornings without readiness or without a one thing answer are left out")
    func ignoresIncomplete() {
        var records = mornings(
            ready: [true, true, true, true, true],
            other: [false, false, false, false, false]
        )
        records.append(F.record(F.date(2026, 12, 1), offset: 0, done: true, ready: nil))
        records.append(F.record(F.date(2026, 12, 2), offset: 0, done: nil, ready: 5))
        let pattern = JournalPatterns.readiness(records)
        #expect(pattern.readyMornings == 5)
        #expect(pattern.otherMornings == 5)
        #expect(JournalPatterns.readiness([]).verdict == .notEarned(.noDays))
    }
}

struct DayEndingsPatternTests {
    @Test("The three-way split counts days stopped early, ended by the lock, and run over")
    func split() {
        let days = F.days(from: firstMonday, count: 6)
        let records = [
            F.record(days[0], offset: -20),
            F.record(days[1], offset: -5),
            F.record(days[2], offset: 0),
            F.record(days[3], offset: 15),
            F.record(days[4], offset: 30),
            F.record(days[5], offset: nil)
        ]
        let pattern = JournalPatterns.dayEndings(records)
        #expect(pattern.verdict == .earned(DayEndingsFinding(
            stoppedBeforeCurfew: 2, endedByLock: 1, ranOver: 2, days: 5
        )))
        #expect(JournalPatterns.dayEndings([]).verdict == .notEarned(.noDays))
    }

    @Test("Patterns read the twelve weeks to the period's end, or the whole year")
    func windows() {
        let calendar = F.utc
        let october = JournalPeriod.containing(
            F.date(2026, 10, 12),
            range: .month,
            calendar: calendar
        )
        let window = JournalPatterns.window(for: october, calendar: calendar)
        #expect(window.end == F.date(2026, 11, 1))
        #expect(window.start == F.date(2026, 8, 9))
        let year = JournalPeriod.containing(F.date(2026, 10, 12), range: .year, calendar: calendar)
        #expect(JournalPatterns.window(for: year, calendar: calendar) == year.interval)
    }
}
