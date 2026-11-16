@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Chart geometry and the screen's states.
extension JournalPresentationTests {
    // MARK: - Chart

    @Test("The chart scale rounds to half hours and widens its step for long spans")
    func chartScale() {
        let small = JournalChartScale(offsets: [-20, 0, 15])
        #expect(small.top == 90)
        #expect(small.bottom == -60)
        #expect(small.step == 30)
        #expect(small.ticks == [90, 60, 30, 0, -30, -60])

        let wide = JournalChartScale(offsets: [-75, 60])
        #expect(wide.top == 90)
        #expect(wide.bottom == -90)
        #expect(wide.step == 60)
        #expect(wide.ticks == [60, 0, -60])

        let empty = JournalChartScale(offsets: [])
        #expect(empty.top == 90)
        #expect(empty.bottom == -30)
        #expect(empty.ticks == [90, 60, 30, 0, -30])
    }

    @Test("Tick labels name curfew, early and over")
    func tickLabels() {
        #expect(format.tickLabel(0) == "Curfew")
        #expect(format.tickLabel(60) == "1h early")
        #expect(format.tickLabel(-30) == "30m over")
    }

    @Test("The year grid bins every day on the seven-step scale")
    func heatBins() {
        #expect(JournalHeatBin(offset: -60) == .early3)
        #expect(JournalHeatBin(offset: -45) == .early3)
        #expect(JournalHeatBin(offset: -44) == .early2)
        #expect(JournalHeatBin(offset: -15) == .early2)
        #expect(JournalHeatBin(offset: -1) == .early1)
        #expect(JournalHeatBin(offset: 0) == .atCurfew)
        #expect(JournalHeatBin(offset: 15) == .over1)
        #expect(JournalHeatBin(offset: 30) == .over2)
        #expect(JournalHeatBin(offset: 31) == .over3)
        #expect(JournalHeatBin(offset: nil) == .noRecord)
    }

    @Test("Columns cover the period's working days, marking days with nothing recorded")
    func columns() {
        let records = [
            record(day(2026, 11, 9), offset: -20),
            record(day(2026, 11, 11), offset: nil, thing: "Old day")
        ]
        let screen = screen(
            records,
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        let days = screen.days
        #expect(days.map { calendar.component(.day, from: $0.day) } == [9, 10, 11, 12])
        #expect(days[0].offset == -20)
        #expect(days[1].kind == .nothingRecorded)
        #expect(days[2].kind == .noStopTime)
        #expect(days[0].startsWeek)
        // Days with no stop time stay out of every count.
        #expect(screen.summary.daysWithStop == 1)
        #expect(days[2].accessibilityLabel
            == "Wed, Nov 11. No stop time recorded. Did the one thing: Old day. Felt ready 4 of 5.")
        #expect(days[0].accessibilityLabel
            == "Mon, Nov 9. Stopped 5:40 PM, 20m before curfew. You called it a day. "
            + "Did the one thing: Ship the billing migration. Felt ready 4 of 5.")
    }

    @Test("Only the earliest and latest days carry a stop time label")
    func extremes() {
        let records = [
            record(day(2026, 11, 9), offset: -20),
            record(day(2026, 11, 10), offset: -45),
            record(day(2026, 11, 11), offset: 30, overrideMinutes: 30, reason: "Production down"),
            record(day(2026, 11, 12), offset: 15)
        ]
        let screen = screen(
            records,
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(screen.days.map(\.extremeLabel) == [nil, "5:15 PM", "6:30 PM", nil])
    }

    // MARK: - States

    @Test("No records at all is the first-days state")
    func noHistory() {
        let screen = screen(
            [],
            range: .month,
            containing: day(2026, 11, 3),
            today: day(2026, 11, 3)
        )
        #expect(screen.state == .noHistory)
    }

    @Test("A period without working days says so instead of counting zeros")
    func noWorkingDays() {
        let screen = screen(
            [record(day(2026, 10, 1), offset: -10)],
            range: .week,
            containing: day(2026, 11, 2),
            today: day(2026, 11, 13)
        )
        #expect(screen.state == .noWorkingDays)
        #expect(screen.headline == "No working days were recorded in this week.")
    }

    @Test("Days recorded before stop times existed are shown but not counted")
    func noStops() {
        let screen = screen(
            [record(day(2026, 11, 9), offset: nil)],
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(screen.state == .noStopTimes)
        #expect(screen.headline == "These days were recorded before Curfew noted stop times.")
    }

    @Test("Navigation stops at today and at the first recorded period")
    func navigation() {
        let records = [record(day(2026, 11, 2), offset: -10), record(day(2026, 11, 9), offset: 0)]
        let current = screen(
            records,
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        #expect(current.canGoBack)
        #expect(!current.canGoForward)
        let first = screen(
            records,
            range: .week,
            containing: day(2026, 11, 2),
            today: day(2026, 11, 13)
        )
        #expect(!first.canGoBack)
        #expect(first.canGoForward)
    }
}
