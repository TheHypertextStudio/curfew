@testable import CurfewKit
import Foundation
import Testing

private typealias F = JournalFixture

struct JournalSummaryTests {
    @Test("A period summary counts how days ended, extra time, the one thing and readiness")
    func summaryDefinitions() throws {
        let days = F.days(from: F.date(2026, 11, 16), count: 5)
        let records = [
            F.record(days[0], offset: -30, done: true, ready: 5),
            F.record(days[1], offset: 0, done: false, ready: 3),
            F.record(days[2], offset: 15, done: true, ready: 4, extensionMinutes: 15),
            F.record(
                days[3],
                offset: 45,
                done: nil,
                ready: nil,
                overrideMinutes: 30,
                extensionMinutes: 15
            ),
            F.record(days[4], offset: nil, done: false, ready: 2)
        ]
        let summary = JournalSummary(records: records)

        #expect(summary.days == 5)
        #expect(summary.daysWithStop == 4)
        #expect(summary.stoppedBeforeCurfew == 1)
        #expect(summary.endedByLock == 1)
        #expect(summary.ranOver == 2)
        #expect(summary.calledItADay == 1)
        #expect(summary.extraMinutes == 60)
        #expect(summary.extraNights == 2)
        #expect(summary.oneThingAnswered == 4)
        #expect(summary.oneThingDone == 2)
        #expect(summary.oneThingRate == 0.5)
        #expect(summary.stoppedBeforeCurfewRate == 0.25)
        #expect(try #require(summary.readinessAverage) == 3.5)
        // Offsets -30, 0, 15, 45: the middle pair averages to 7.5, rounded up.
        #expect(summary.medianStopOffsetMinutes == 8)
    }

    @Test("Median matches the prototype: middle value, halves rounded toward later")
    func medianRounding() {
        #expect(JournalMath.median([]) == nil)
        #expect(JournalMath.median([-20, 5, -10]) == -10)
        #expect(JournalMath.median([-15, 0]) == -7)
        #expect(JournalMath.median([10, 21]) == 16)
        #expect(JournalMath.median([-21, -10]) == -15)
    }
}

struct JournalPeriodTests {
    @Test("A week runs from the calendar's first weekday and links to its neighbours")
    func weekPeriods() {
        let calendar = F.utc
        let week = JournalPeriod.containing(
            F.date(2026, 11, 18, 15),
            range: .week,
            calendar: calendar
        )
        #expect(week.range == .week)
        #expect(week.interval.start == F.date(2026, 11, 16))
        #expect(week.interval.end == F.date(2026, 11, 23))
        #expect(week.previous(calendar: calendar).interval.start == F.date(2026, 11, 9))
        #expect(week.next(calendar: calendar).interval.start == F.date(2026, 11, 23))

        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let usWeek = JournalPeriod.containing(
            F.date(2026, 11, 18), range: .week, calendar: sundayFirst
        )
        #expect(usWeek.interval.start == F.date(2026, 11, 15))
    }

    @Test("Months and years run on calendar boundaries")
    func monthAndYear() {
        let calendar = F.utc
        let month = JournalPeriod.containing(
            F.date(2026, 11, 18),
            range: .month,
            calendar: calendar
        )
        #expect(month.interval.start == F.date(2026, 11, 1))
        #expect(month.interval.end == F.date(2026, 12, 1))
        #expect(month.previous(calendar: calendar).interval.start == F.date(2026, 10, 1))
        let year = JournalPeriod.containing(F.date(2026, 11, 18), range: .year, calendar: calendar)
        #expect(year.interval.start == F.date(2026, 1, 1))
        #expect(year.interval.end == F.date(2027, 1, 1))
        #expect(year.previous(calendar: calendar).interval.start == F.date(2025, 1, 1))
    }

    @Test("A period selects the records whose day falls inside it")
    func selectsRecords() {
        let calendar = F.utc
        let records = F.days(from: F.date(2026, 11, 13), count: 12).map {
            F.record($0, offset: 0)
        }
        let week = JournalPeriod.containing(F.date(2026, 11, 18), range: .week, calendar: calendar)
        #expect(week.records(from: records).map(\.day) == F.days(
            from: F.date(2026, 11, 16), count: 7
        ))
        #expect(week.summary(of: records).days == 7)
    }
}
