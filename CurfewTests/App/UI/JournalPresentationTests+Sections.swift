@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Words, patterns and the day table.
extension JournalPresentationTests {
    // MARK: - Words, patterns and the table

    @Test("Overrides list newest first with their reasons; more time is totalled")
    func words() {
        let records = [
            record(day(2026, 11, 9), offset: 30, overrideMinutes: 30, reason: "First reason."),
            record(day(2026, 11, 10), offset: 15, extensionMinutes: 15),
            record(day(2026, 11, 11), offset: 45, overrideMinutes: 45, reason: "Second reason."),
            record(day(2026, 11, 12), offset: 30, extensionMinutes: 30)
        ]
        let screen = screen(
            records,
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(screen.words.overrides.map(\.title)
            == ["Wed, Nov 11 · 45m override", "Mon, Nov 9 · 30m override"])
        #expect(screen.words.overrides.map(\.reasons) == [["Second reason."], ["First reason."]])
        #expect(screen.words.closingTitle == "More time, 2 times")
        #expect(screen.words.closingLine == "45m in all. More time does not ask for a reason.")
    }

    @Test("Without overrides or more time the section still reads plainly")
    func emptyWords() {
        let screen = screen(
            [record(day(2026, 11, 9), offset: -10)],
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(screen.words.overrides.isEmpty)
        #expect(screen.words.emptyLine == "You did not ask to get back in after the lock.")
        #expect(screen.words.closingTitle == "No more time")
        #expect(screen.words.closingLine == "You did not ask for more minutes before the lock.")
    }

    @Test("Patterns say how many days they rest on, or why there is nothing yet")
    func patterns() {
        let screen = screen(
            [record(day(2026, 11, 9), offset: -10)],
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(screen.patterns.basis == "From the 12 weeks to Nov 13, 1 working day.")
        #expect(screen.patterns.weekday.sentence == "No weekday stands out yet.")
        #expect(screen.patterns.weekday.note == "Needs more than one weekday to compare.")
        #expect(screen.patterns.readiness.sentence == "Nothing to report yet.")
        #expect(screen.patterns.readiness.note
            == "Needs five mornings of each kind. The fewer kind has 0.")
        #expect(screen.patterns.endings.sentence
            == "You ended 1 day yourself.")
        #expect(screen.patterns.endings.note == "From 1 day with a stop time.")
    }

    @Test("The sample earns the weekday pattern with its day count")
    func earnedPatterns() {
        let sample = JournalSampleData.make(endingOn: day(2026, 11, 13), calendar: calendar)
        let screen = screen(
            sample.records,
            range: .year,
            containing: day(2026, 11, 13),
            today: day(2026, 11, 13)
        )
        #expect(screen.patterns.weekday.isEarned)
        #expect(screen.patterns.weekday.sentence.hasSuffix("later than your other days."))
        #expect(screen.patterns.weekday.note.hasPrefix("From "))
        #expect(screen.patterns.readiness.isEarned)
        #expect(screen.patterns.readiness.sentence.hasPrefix("You did the one thing on "))
    }

    @Test("Year range lists the latest twelve days and offers the rest")
    func yearTable() {
        let sample = JournalSampleData.make(endingOn: day(2026, 11, 13), calendar: calendar)
        let screen = screen(
            sample.records,
            range: .year,
            containing: day(2026, 11, 13),
            today: day(2026, 11, 13)
        )
        #expect(screen.rows.count > 12)
        #expect(screen.collapsedRowLimit == 12)
        #expect(screen.rows.first?.day == sample.records.last?.day)
        #expect(screen.showAllTitle == "Show all \(screen.rows.count) days")
        let week = self.screen(
            sample.records,
            range: .week,
            containing: day(2026, 11, 13),
            today: day(2026, 11, 13)
        )
        #expect(week.collapsedRowLimit == nil)
    }

    @Test("A table row is a full sentence for VoiceOver and opens that evening")
    func tableRows() throws {
        let records = [record(
            day(2026, 11, 10),
            offset: 45,
            done: false,
            ready: 2,
            overrideMinutes: 45,
            reason: "Production is down."
        )]
        let screen = screen(
            records,
            range: .week,
            containing: day(2026, 11, 10),
            today: day(2026, 11, 13)
        )
        let row = try #require(screen.rows.first)
        #expect(row.dayLabel == "Tue, Nov 10")
        #expect(row.stopped == "6:45 PM")
        #expect(row.against == "45m over")
        #expect(row.ready == "2 of 5")
        #expect(row.details.first { $0.term == "How it ended" }?.value == "Override, 45m")
        #expect(row.details.first { $0.term == "Your reason" }?.value == "“Production is down.”")
    }
}
