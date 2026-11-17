@testable import Curfew
import CurfewAtmosphere
import CurfewKit
import Foundation
import SwiftUI
import Testing

/// The time card's two punch patterns and the person's choices of stock,
/// sky, punches and headline.
struct JournalTimeCardTests {
    let helper = JournalYearReviewTests()

    var calendar: Calendar {
        helper.calendar
    }

    var format: JournalFormat {
        helper.format
    }

    func calendarPunches(
        _ records: [JournalDayRecord],
        working: Set<Weekday> = JournalYearReviewTests.weekdays,
        firstWeekday: Int = 2
    ) -> JournalTimeCardCalendar {
        let calendar = JournalYearReviewTests.calendar(firstWeekday: firstWeekday)
        return JournalTimeCardCalendar(
            year: 2026,
            records: records,
            workingWeekdays: working,
            format: JournalFormat(calendar: calendar, locale: Locale(identifier: "en_US"))
        )
    }

    /// Evenings the person ended themselves at each offset.
    func called(_ offsets: [Int]) -> [JournalDayRecord] {
        helper.records(offsets, cause: .calledItADay)
    }

    // MARK: - Calendar

    @Test func everyWorkingDayOfTheYearHasASlot() {
        let punches = calendarPunches([])
        // 2026 has 261 weekdays.
        #expect(punches.slots.count == 261)
        #expect(punches.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(punches.holeCount == 0)
    }

    @Test func theHolesAreTheEveningsOutBeforeCurfew() {
        let offsets: [Int?] = (0 ..< 40).map { $0 % 3 == 0 ? 0 : $0 % 3 == 1 ? -15 : 25 }
        let records = helper.records(offsets)
        let punches = calendarPunches(records)
        let early = JournalYearInReview(records: records, calendar: calendar)
            .daysStoppedBeforeCurfew
        #expect(punches.holeCount == early)
        let punchedDays = Set(punches.slots.filter(\.isPunched).map(\.day))
        let earlyDays = Set(records.filter { $0.outcome == .stoppedBeforeCurfew }.map(\.day))
        #expect(punchedDays == earlyDays)
    }

    @Test func weeksAreColumnsInTwoHalfYearBandsOfEqualWidth() throws {
        let punches = calendarPunches([])
        #expect(punches.columnsPerBand == 27)
        #expect(punches.slots.allSatisfy { $0.column < punches.columnsPerBand })
        #expect(Set(punches.slots.map(\.band)) == [0, 1])
        func slot(_ month: Int, _ day: Int) throws -> JournalTimeCardCalendar.Slot {
            try #require(punches.slots.first { $0.day == helper.day(2026, month, day) })
        }
        // Thursday Jan 1 opens the first column; Monday Jan 5 starts the second.
        let first = try slot(1, 1)
        #expect(first.band == 0 && first.column == 0 && first.row == 3)
        let monday = try slot(1, 5)
        #expect(monday.column == 1 && monday.row == 0)
        #expect(try slot(1, 6).column == 1)
        // The second band opens with the week July begins in.
        let july = try slot(7, 1)
        #expect(july.band == 1 && july.column == 0)
        #expect(try slot(6, 26).band == 0)
        #expect(try slot(7, 6).column == 1)
    }

    @Test func monthsAreLabelledWhereTheyBegin() throws {
        let punches = calendarPunches([])
        #expect(punches.months.map(\.name) == [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
        ])
        let july = try #require(punches.months.first { $0.name == "Jul" })
        #expect(july.band == 1 && july.column == 0)
        let march = try #require(punches.months.first { $0.name == "Mar" })
        let firstOfMarch = try #require(punches.slots.first { $0.day == helper.day(2026, 3, 2) })
        #expect(march.band == firstOfMarch.band && march.column == firstOfMarch.column)
    }

    @Test func rowsFollowTheWeekOrderOfThePersonsCalendar() {
        let weekend: Set<Weekday> = [.saturday, .sunday, .monday, .tuesday, .wednesday]
        #expect(calendarPunches([], working: weekend, firstWeekday: 1).weekdays
            == [.sunday, .monday, .tuesday, .wednesday, .saturday])
        #expect(calendarPunches([], working: weekend, firstWeekday: 2).weekdays
            == [.monday, .tuesday, .wednesday, .saturday, .sunday])
    }

    @Test func everyDayWorkersGetSevenRowsThatStillFit() {
        let punches = calendarPunches([], working: Set(Weekday.allCases))
        #expect(punches.weekdays.count == 7)
        #expect(punches.slots.count == 365)
        let grid = JournalTimeCardLayout.calendarGrid(rows: 7, columns: punches.columnsPerBand)
        #expect(grid.height <= JournalTimeCardLayout.punchArea.height)
        #expect(grid.holeRadius * 2 >= JournalTimeCardLayout.minimumHoleDiameter)
    }

    @Test func aDayWorkedOutsideTheScheduleStillGetsItsRow() {
        let saturday = helper.record(helper.day(2026, 2, 7), offset: -20)
        let punches = calendarPunches([saturday])
        #expect(punches.weekdays == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        #expect(punches.holeCount == 1)
    }

    @Test func theCalendarGridIsSquareAcrossTheFullWidth() {
        let grid = JournalTimeCardLayout.calendarGrid(rows: 5, columns: 27)
        #expect(abs(grid.columnPitch * 27 - JournalTimeCardLayout.contentWidth) < 1e-9)
        #expect(grid.rowPitch == grid.columnPitch)
    }

    // MARK: - Skyline

    @Test func onlyEveningsThePersonEndedGetAHole() {
        var records = called([-30, -20, -10, -5, 5])
        records += helper.records([0, 0, 15], cause: .lock)
        let skyline = JournalTimeCardSkyline(records: records, format: format)
        #expect(skyline.holeCount == 5)
        #expect(skyline.bins.map(\.count).reduce(0, +) == 5)
    }

    @Test func theCurfewLineSplitsEarlyFromLate() {
        let skyline = JournalTimeCardSkyline(records: called([-1, -1, 0, 3]), format: format)
        #expect(skyline.binMinutes == 5)
        #expect(skyline.bins.first { $0.bin == -1 }?.count == 2)
        #expect(skyline.bins.first { $0.bin == 0 }?.count == 2)
        #expect(skyline.bins.contains { $0.bin < 0 })
        #expect(skyline.bins.contains { $0.bin >= 0 })
    }

    @Test func aGentleSpreadUsesFiveMinuteColumns() {
        let skyline = JournalTimeCardSkyline(records: called(Array(-30 ... -1)), format: format)
        #expect(skyline.binMinutes == 5)
        #expect(skyline.columnsPerBin == 1)
        #expect(skyline.earlyLabel == "30m early")
        #expect(skyline.lateLabel == "5m over")
    }

    @Test func aWideSpreadWidensTheColumnsToTenMinutes() {
        let skyline = JournalTimeCardSkyline(records: called(Array(-120 ... 59)), format: format)
        #expect(skyline.binMinutes == 10)
        #expect(skyline.columnsPerBin == 1)
        #expect(skyline.pitch >= JournalTimeCardLayout.comfortablePitch)
    }

    @Test func theWidestSpreadUsesFifteenMinutes() {
        let skyline = JournalTimeCardSkyline(
            records: called(Array(stride(from: -190, through: 100, by: 3))), format: format
        )
        #expect(skyline.binMinutes == 15)
        #expect(skyline.pitch >= JournalTimeCardLayout.comfortablePitch)
    }

    @Test func aPeakyYearKeepsEveryHoleAtAComfortableSize() {
        // 180 evenings: most a few minutes early, a long early tail, a few over.
        let offsets = (0 ..< 100).map { -1 - $0 % 10 }
            + (0 ..< 50).map { -11 - $0 % 20 }
            + (0 ..< 30).map { 1 + $0 % 20 }
        let skyline = JournalTimeCardSkyline(records: called(offsets), format: format)
        #expect(skyline.holeCount == 180)
        #expect(skyline.pitch >= JournalTimeCardLayout.minimumPitch)
        let size = skyline.patternSize
        #expect(size.width <= JournalTimeCardLayout.contentWidth + 1e-9)
        #expect(size.height <= JournalTimeCardLayout.skylineHoleHeight + 1e-9)
    }

    @Test func farTailsGatherInTheEdgeColumnsAndTheLabelsSaySo() {
        let offsets = Array(repeating: -10, count: 40) + [-400, 300]
        let skyline = JournalTimeCardSkyline(records: called(offsets), format: format)
        #expect(skyline.holeCount == 42)
        #expect(skyline.earlyLabel.hasSuffix("+ early"))
        #expect(skyline.lateLabel.hasSuffix("+ over"))
    }

    @Test func holesSitOnAStrictGrid() {
        let skyline = JournalTimeCardSkyline(records: called(Array(-30 ... 10)), format: format)
        let holes = skyline.holes
        #expect(holes.count == skyline.holeCount)
        for hole in holes {
            let column = (hole.centerX - skyline.patternOrigin.x) / skyline.pitch - 0.5
            #expect(abs(column - column.rounded()) < 1e-9)
        }
        #expect(Set(holes.map(\.radius)).count == 1)
    }

    // MARK: - Choices

    @Test func untilChosenTheCardFollowsTheAppearanceAndTheAppsSky() {
        let choices = JournalTimeCardChoices()
        #expect(choices.resolved(colorScheme: .dark, appSky: .polar) == JournalTimeCardStyle(
            stock: .night, sky: .polar, punches: .calendar, headline: .eveningsOut
        ))
        #expect(choices.resolved(colorScheme: .light, appSky: .desert).stock == .paper)
        #expect(choices.resolved(colorScheme: .light, appSky: .desert).sky == .desert)
    }

    @Test func aChoiceHoldsWhateverTheAppearance() {
        var choices = JournalTimeCardChoices()
        choices.stock = .night
        choices.sky = .sundown
        #expect(choices.resolved(colorScheme: .light, appSky: .polar).stock == .night)
        #expect(choices.resolved(colorScheme: .light, appSky: .polar).sky == .sundown)
    }

    @Test func theAppsSkyMapsFromItsPalette() {
        #expect(JournalTimeCardSky(palette: .standard) == .sundown)
        #expect(JournalTimeCardSky(palette: .desert) == .desert)
        #expect(JournalTimeCardSky(palette: .polar) == .polar)
        #expect(JournalTimeCardSky.desert.palette == .desert)
    }

    @Test func choicesPersist() throws {
        let suite = "JournalTimeCardTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = JournalTimeCardStore(defaults: defaults)
        #expect(store.load() == JournalTimeCardChoices())
        var choices = JournalTimeCardChoices()
        choices.stock = .paper
        choices.punches = .skyline
        choices.headline = .longestRun
        store.save(choices)
        #expect(JournalTimeCardStore(defaults: defaults).load() == choices)
    }

    @Test func unreadableStoredChoicesFallBackToTheDefaults() throws {
        let suite = "JournalTimeCardTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: JournalTimeCardStore.key)
        #expect(JournalTimeCardStore(defaults: defaults).load() == JournalTimeCardChoices())
    }

    @Test func shuffleAlwaysChangesTheCardAndChoosesEverything() {
        let current = JournalTimeCardStyle(
            stock: .night, sky: .sundown, punches: .calendar, headline: .eveningsOut
        )
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 50 {
            let shuffled = JournalTimeCardChoices.shuffled(from: current, using: &generator)
            #expect(shuffled.stock != nil && shuffled.sky != nil)
            #expect(shuffled.punches != nil && shuffled.headline != nil)
            #expect(shuffled.resolved(colorScheme: .dark, appSky: .sundown) != current)
        }
    }
}
