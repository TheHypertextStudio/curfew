@testable import CurfewKit
import Foundation
import Testing

private typealias F = JournalFixture

struct JournalTrendTests {
    private let calendar = F.utc

    @Test("Each metric reads its value from a period summary")
    func metricValues() {
        let days = F.days(from: F.date(2026, 11, 16), count: 4)
        let summary = JournalSummary(records: [
            F.record(days[0], offset: -20, done: true, ready: 4),
            F.record(days[1], offset: 0, done: false, ready: 2),
            F.record(days[2], offset: 30, done: true, ready: 3),
            F.record(days[3], offset: -10, done: true, ready: 5)
        ])
        #expect(JournalMetric.stoppedBeforeCurfewRate.value(in: summary) == 0.5)
        #expect(JournalMetric.oneThingRate.value(in: summary) == 0.75)
        #expect(JournalMetric.extraMinutes.value(in: summary) == 30)
        #expect(JournalMetric.readinessAverage.value(in: summary) == 3.5)
        #expect(JournalMetric.medianStopOffset.value(in: summary) == -5)
        #expect(JournalMetric.oneThingRate.value(in: JournalSummary(records: [])) == nil)
    }

    @Test("Week trend lines cover the twelve weeks to the period, skipping empty weeks")
    func weeklyTrail() throws {
        // Fourteen weeks of Mondays, with week 10 missing.
        let mondays = (0 ..< 14).compactMap { index -> Date? in
            index == 10 ? nil : calendar.date(
                byAdding: .day,
                value: index * 7,
                to: F.date(2026, 8, 17)
            )
        }
        let records = mondays.enumerated().map { index, day in
            F.record(day, offset: index.isMultiple(of: 2) ? -15 : 0)
        }
        let period = try JournalPeriod.containing(
            #require(mondays.last),
            range: .week,
            calendar: calendar
        )
        let points = JournalTrend.points(
            .stoppedBeforeCurfewRate, endingAt: period, records: records, calendar: calendar
        )
        #expect(points.count == 11)
        #expect(points.last?.period == period)
        #expect(points.first?.period.interval.start == F.date(2026, 8, 31))
        #expect(points.map(\.period.interval.start) == points.map(\.period.interval.start).sorted())
    }

    @Test("Month trend lines cover twelve trailing months; year lines cover the year's months")
    func monthlyAndYearlyTrail() {
        let records = (1 ... 11).map { month in
            F.record(F.date(2026, month, 10), offset: month * -1, done: month.isMultiple(of: 2))
        }
        let october = JournalPeriod.containing(
            F.date(2026, 10, 10),
            range: .month,
            calendar: calendar
        )
        let monthly = JournalTrend.points(
            .medianStopOffset, endingAt: october, records: records, calendar: calendar
        )
        #expect(monthly.count == 10)
        #expect(monthly.last?.value == -10)

        let year = JournalPeriod.containing(F.date(2026, 10, 10), range: .year, calendar: calendar)
        let yearly = JournalTrend.points(
            .medianStopOffset, endingAt: year, records: records, calendar: calendar
        )
        #expect(yearly.count == 11)
        #expect(yearly.allSatisfy { $0.period.range == .month })
        #expect(yearly.first?.value == -1)
    }
}

struct JournalYearInReviewTests {
    @Test(
        "Year totals count early stops, the typical stop, one thing days, extra time and the longest run"
    )
    func totals() {
        let days = F.days(from: F.date(2026, 3, 2), count: 9)
        let records = [
            F.record(days[0], offset: -10, done: true),
            F.record(days[1], offset: -20, done: true),
            F.record(days[2], offset: 0, done: false), // breaks the run
            F.record(days[3], offset: -5, done: true),
            F.record(days[4], offset: -30),
            F.record(days[5], offset: -15),
            F.record(days[6], offset: nil, done: true), // unknown stop breaks the run
            F.record(days[7], offset: 45, overrideMinutes: 30, extensionMinutes: 15),
            F.record(days[8], offset: -40)
        ]
        let review = JournalYearInReview(records: records, calendar: F.utc)
        #expect(review.days == 9)
        #expect(review.daysStoppedBeforeCurfew == 6)
        #expect(review.oneThingDays == 4)
        #expect(review.extraMinutes == 45)
        #expect(review.longestRunBeforeCurfew == 3)
        // Offsets -40 -30 -20 -15 -10 -5 0 45: middle pair -15 and -10.
        #expect(review.medianStopOffsetMinutes == -12)
        #expect(review.typicalStopMinuteOfDay == 18 * 60 - 12)
    }

    @Test("A stop after midnight counts past twenty-four hours for the typical stop")
    func afterMidnightStop() {
        let day = F.date(2026, 3, 2)
        let curfew = F.date(2026, 3, 2, 23, 30)
        let late = JournalDayRecord(
            day: day,
            ending: DayEnding(
                cause: .lock, stoppedAt: curfew.addingTimeInterval(F.minutes(45)),
                scheduledCurfew: curfew
            )
        )
        let review = JournalYearInReview(records: [late], calendar: F.utc)
        #expect(review.typicalStopMinuteOfDay == 24 * 60 + 15)
    }

    @Test("An empty year has zero totals and no typical stop")
    func empty() {
        let review = JournalYearInReview(records: [], calendar: F.utc)
        #expect(review.days == 0)
        #expect(review.daysStoppedBeforeCurfew == 0)
        #expect(review.longestRunBeforeCurfew == 0)
        #expect(review.typicalStopMinuteOfDay == nil)
        #expect(review.medianStopOffsetMinutes == nil)
    }
}

struct JournalRetentionTests {
    @Test(
        "The activity log keeps at least 400 days so a full year and its comparison stay readable"
    )
    func retentionCoversYearView() throws {
        #expect(JournalRetention.minimumDays >= 400)
        #expect(JournalRetention.activitySeconds >= 400 * 86400)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-journal-retention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ActivityStore(directory: directory)
        let now = F.date(2026, 11, 16, 12)
        let kept = now.addingTimeInterval(-399 * 86400)
        let dropped = now.addingTimeInterval(-401 * 86400)
        try store.append(F.dayEnd(.lock, curfew: kept, offset: 0))
        try store.append(F.dayEnd(.lock, curfew: dropped, offset: 0))
        try store.append(OneThingOutcome.event(done: true, at: kept))

        try store.trimEvents(olderThan: JournalRetention.activitySeconds, now: now)

        let remaining = try store.events(in: .distantPast ... .distantFuture)
        #expect(remaining.map(\.timestamp) == [kept, kept])
        #expect(Set(remaining.map(\.kind)) == [.dayEnded, .oneThingAnswered])
    }
}
