@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Debug-only Journal sample data drives the Journal's snapshots and
/// previews, so it must be deterministic and exercise every definition.
struct JournalSampleDataTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var lastDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 13))!
    }

    @Test("The same end date always produces the same eleven months")
    func deterministic() {
        let first = JournalSampleData.make(endingOn: lastDay, calendar: calendar)
        let second = JournalSampleData.make(endingOn: lastDay, calendar: calendar)
        #expect(first.events.map(\.timestamp) == second.events.map(\.timestamp))
        #expect(first.events.map(\.note) == second.events.map(\.note))
        #expect(first.reflections.map(\.answers) == second.reflections.map(\.answers))
        #expect(first.records == second.records)
    }

    @Test("Only working days have records and every record is complete")
    func shape() throws {
        let sample = JournalSampleData.make(endingOn: lastDay, calendar: calendar)
        let records = sample.records
        let first = try #require(records.first?.day)
        let span = calendar.dateComponents([.day], from: first, to: lastDay).day ?? 0
        #expect(span >= 300 && span <= 345)
        #expect(records.count > 200)
        #expect(records.allSatisfy { record in
            let weekday = calendar.component(.weekday, from: record.day)
            return weekday != 1 && weekday != 7
        })
        #expect(records.allSatisfy { $0.ending != nil && $0.oneThing != nil })
        #expect(records.allSatisfy { $0.oneThingDone != nil && $0.readiness != nil })
        #expect(records.contains { !$0.overrideReasons.isEmpty })
    }

    @Test("The sample earns every pattern and shows all three endings")
    func earnsPatterns() {
        let records = JournalSampleData.make(endingOn: lastDay, calendar: calendar).records
        let summary = JournalSummary(records: records)
        #expect(summary.stoppedBeforeCurfew > 0)
        #expect(summary.endedByLock > 0)
        #expect(summary.ranOver > 0)
        #expect(JournalPatterns.weekday(records, calendar: calendar).verdict.isEarned)
        #expect(JournalPatterns.readiness(records).verdict.isEarned)
        #expect(JournalYearInReview(records: records, calendar: calendar)
            .longestRunBeforeCurfew > 1)
    }
}
