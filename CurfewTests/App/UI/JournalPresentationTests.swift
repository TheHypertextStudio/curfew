@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Journal screen's words, numbers and chart geometry, built from day
/// records without any view. Mirrors the approved Journal prototype.
struct JournalPresentationTests {
    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    var calendar: Calendar {
        Self.calendar
    }

    var format: JournalFormat {
        JournalFormat(calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    /// A day that ended `offset` minutes from a 6:00 PM curfew.
    func record(
        _ date: Date,
        offset: Int?,
        done: Bool? = true,
        ready: Int? = 4,
        thing: String? = "Ship the billing migration",
        overrideMinutes: Int = 0,
        reason: String? = nil,
        extensionMinutes: Int = 0
    ) -> JournalDayRecord {
        let curfew = at(date, 18)
        let ending = offset.map { offset in
            DayEnding(
                cause: offset < 0 ? .calledItADay : .lock,
                stoppedAt: curfew.addingTimeInterval(TimeInterval(offset - overrideMinutes) * 60),
                scheduledCurfew: curfew
            )
        }
        return JournalDayRecord(
            day: date,
            ending: ending,
            extensionMinutes: extensionMinutes,
            overrideMinutes: overrideMinutes,
            overrideReasons: reason.map { [$0] } ?? [],
            oneThing: thing,
            oneThingDone: done,
            readiness: ready.map { JournalRating(value: $0, scale: 5) }
        )
    }

    func screen(
        _ records: [JournalDayRecord],
        range: JournalRange,
        containing date: Date,
        today: Date
    ) -> JournalScreen {
        JournalScreen(
            records: records,
            period: JournalPeriod.containing(date, range: range, calendar: calendar),
            today: today,
            workingWeekdays: weekdays,
            format: format
        )
    }

    // MARK: - Formatting

    @Test("Durations read as hours and minutes without a leading zero hour")
    func durations() {
        #expect(format.duration(45) == "45m")
        #expect(format.duration(-45) == "45m")
        #expect(format.duration(60) == "1h")
        #expect(format.duration(75) == "1h 15m")
        #expect(format.duration(0) == "0m")
    }

    @Test("Offsets say early, over, or at curfew in both lengths")
    func offsets() {
        #expect(format.relative(-18) == "18m before curfew")
        #expect(format.relative(45) == "45m over")
        #expect(format.relative(0) == "at curfew")
        #expect(format.relativeShort(-18) == "18m early")
        #expect(format.relativeShort(90) == "1h 30m over")
        #expect(format.relativeShort(0) == "At curfew")
    }

    @Test("Period labels follow the prototype: a working week, a month, a year")
    func periodLabels() {
        let week = JournalPeriod.containing(day(2026, 11, 11), range: .week, calendar: calendar)
        #expect(format.periodLabel(week, workingWeekdays: weekdays) == "Nov 9 to 13")
        let spanning = JournalPeriod.containing(
            day(2026, 10, 28),
            range: .week,
            calendar: calendar
        )
        #expect(format.periodLabel(spanning, workingWeekdays: weekdays) == "Oct 26 to 30")
        let crossing = JournalPeriod.containing(
            day(2026, 12, 1),
            range: .week,
            calendar: calendar
        )
        #expect(format.periodLabel(crossing, workingWeekdays: weekdays) == "Nov 30 to Dec 4")
        let month = JournalPeriod.containing(day(2026, 10, 5), range: .month, calendar: calendar)
        #expect(format.periodLabel(month, workingWeekdays: weekdays) == "October 2026")
        let year = JournalPeriod.containing(day(2026, 10, 5), range: .year, calendar: calendar)
        #expect(format.periodLabel(year, workingWeekdays: weekdays) == "2026")
    }

    @Test("The previous period is named the way the comparison sentence needs it")
    func previousNames() {
        let week = JournalPeriod.containing(day(2026, 11, 11), range: .week, calendar: calendar)
        #expect(format.previousName(week) == "the week before")
        let month = JournalPeriod.containing(day(2026, 10, 5), range: .month, calendar: calendar)
        #expect(format.previousName(month) == "September")
        let year = JournalPeriod.containing(day(2026, 10, 5), range: .year, calendar: calendar)
        #expect(format.previousName(year) == nil)
    }

    // MARK: - Headline and tiles

    @Test("The headline gives the three counts in one sentence")
    func headline() {
        let monday = day(2026, 11, 9)
        let records = [
            record(monday, offset: -20),
            record(day(2026, 11, 10), offset: 0),
            record(day(2026, 11, 11), offset: 30),
            record(day(2026, 11, 12), offset: -5)
        ]
        let screen = screen(records, range: .week, containing: monday, today: day(2026, 11, 13))
        #expect(screen.headline
            == "You stopped before curfew on 2 of 4 days. The lock ended 1. 1 ran over.")

        let calm = self.screen(
            [record(monday, offset: -20)],
            range: .week,
            containing: monday,
            today: day(2026, 11, 13)
        )
        #expect(calm.headline
            == "You stopped before curfew on your one day.")
    }

    @Test("The headline leaves out zero clauses and says all plainly", arguments: [
        (4, 0, 0, "You stopped before curfew on all 4 days."),
        (1, 0, 0, "You stopped before curfew on your one day."),
        (3, 1, 0, "You stopped before curfew on 3 of 4 days. The lock ended 1."),
        (3, 0, 2, "You stopped before curfew on 3 of 5 days. 2 ran over."),
        (1, 2, 1, "You stopped before curfew on 1 of 4 days. The lock ended 2. 1 ran over."),
        (0, 5, 0, "The lock ended all 5 days."),
        (0, 1, 0, "The lock ended your one day."),
        (0, 0, 3, "All 3 days ran over."),
        (0, 0, 1, "Your one day ran over."),
        (0, 3, 2, "The lock ended 3 days and 2 ran over."),
        (0, 1, 1, "The lock ended 1 day and 1 ran over.")
    ])
    func headlineClauses(early: Int, lock: Int, over: Int, expected: String) {
        #expect(JournalCountWords.headline(early: early, lock: lock, over: over) == expected)
    }

    @Test("The day endings sentence leaves out zero clauses too", arguments: [
        (12, 6, 3, "You ended 12 days yourself. The lock ended 6. 3 ran over."),
        (1, 0, 0, "You ended 1 day yourself."),
        (5, 0, 2, "You ended 5 days yourself. 2 ran over."),
        (0, 4, 0, "The lock ended all 4 days."),
        (0, 3, 2, "The lock ended 3 days and 2 ran over.")
    ])
    func endingClauses(early: Int, lock: Int, over: Int, expected: String) {
        #expect(JournalCountWords.endings(early: early, lock: lock, over: over) == expected)
    }

    @Test("Comparisons say up, down or same, named for the previous period")
    func comparisons() {
        #expect(JournalTile.comparison(
            current: 0.6, previous: 0.48, range: .month, previousName: "September",
            format: format.percent
        ) == "Up from 48% in September")
        #expect(JournalTile.comparison(
            current: 0.4, previous: 0.48, range: .week, previousName: "the week before",
            format: format.percent
        ) == "Down from 48% the week before")
        #expect(JournalTile.comparison(
            current: 0.481, previous: 0.479, range: .week, previousName: "the week before",
            format: format.percent
        ) == "Same as the week before")
        #expect(JournalTile.comparison(
            current: 0.5, previous: 0.4, range: .year, previousName: nil, format: format.percent
        ) == nil)
        #expect(JournalTile.comparison(
            current: 0.5, previous: nil, range: .month, previousName: "September",
            format: format.percent
        ) == nil)
    }

    @Test("Tiles carry the value, a qualifier, and a comparison with the week before")
    func tiles() {
        let previous = [
            record(day(2026, 11, 2), offset: -10, done: false, ready: 3),
            record(day(2026, 11, 3), offset: 15, done: true, ready: 3)
        ]
        let current = [
            record(day(2026, 11, 9), offset: -20, done: true, ready: 5),
            record(
                day(2026, 11, 10),
                offset: 30,
                done: true,
                ready: 4,
                overrideMinutes: 30,
                reason: "Payroll export failed."
            ),
            record(day(2026, 11, 11), offset: 15, done: false, ready: 4, extensionMinutes: 15)
        ]
        let screen = screen(
            previous + current,
            range: .week,
            containing: day(2026, 11, 9),
            today: day(2026, 11, 13)
        )
        let tiles = screen.tiles
        #expect(tiles.map(\.title) == [
            "Stopped before curfew", "Did the one thing", "Extra time taken",
            "Felt ready in the morning"
        ])
        #expect(tiles[0].value == "33%")
        #expect(tiles[0].qualifier == "1 of 3 days")
        #expect(tiles[0].comparison == "Down from 50% the week before")
        #expect(tiles[1].value == "67%")
        #expect(tiles[1].qualifier == "2 of 3 days")
        #expect(tiles[2].value == "45m")
        #expect(tiles[2].qualifier == "2 nights")
        #expect(tiles[2].comparison == "Up from 15m the week before")
        #expect(tiles[3].value == "4.3")
        #expect(tiles[3].qualifier == "out of 5")
        #expect(tiles[3].comparison == "Up from 3.0 the week before")
    }

    @Test("Extra time reads None when no night ran over, and year range has no comparisons")
    func tilesYear() {
        let records = [record(day(2026, 3, 2), offset: -10), record(day(2026, 3, 3), offset: 0)]
        let screen = screen(
            records,
            range: .year,
            containing: day(2026, 3, 2),
            today: day(2026, 11, 13)
        )
        #expect(screen.tiles[2].value == "None")
        #expect(screen.tiles[2].qualifier == "")
        #expect(screen.tiles.allSatisfy { $0.comparison == nil })
    }
}
