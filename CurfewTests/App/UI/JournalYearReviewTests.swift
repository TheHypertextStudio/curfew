import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import SwiftUI
import Testing

/// The year time card's words, threshold, punches and file name, built from
/// day records without any view.
struct JournalYearReviewTests {
    static func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    var calendar: Calendar {
        Self.calendar()
    }

    var format: JournalFormat {
        JournalFormat(calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A day that ended `offset` minutes from a 6:00 PM curfew. Early days
    /// were called by the person; the rest were ended by the lock unless
    /// `cause` says otherwise.
    func record(
        _ date: Date,
        offset: Int?,
        cause: DayEndCause? = nil,
        done: Bool? = true,
        overrideMinutes: Int = 0,
        reason: String? = nil
    ) -> JournalDayRecord {
        let curfew = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date)!
        let ending = offset.map { offset in
            DayEnding(
                cause: cause ?? (offset < 0 ? .calledItADay : .lock),
                stoppedAt: curfew.addingTimeInterval(TimeInterval(offset - overrideMinutes) * 60),
                scheduledCurfew: curfew
            )
        }
        return JournalDayRecord(
            day: date,
            ending: ending,
            overrideMinutes: overrideMinutes,
            overrideReasons: reason.map { [$0] } ?? [],
            oneThing: "Ship the private billing migration",
            oneThingDone: done
        )
    }

    /// `offsets` on consecutive weekdays from Mon Jan 5, 2026.
    func records(_ offsets: [Int?], cause: DayEndCause? = nil) -> [JournalDayRecord] {
        var date = day(2026, 1, 5)
        return offsets.map { offset in
            while [1, 7].contains(calendar.component(.weekday, from: date)) {
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
            defer { date = calendar.date(byAdding: .day, value: 1, to: date)! }
            return record(date, offset: offset, cause: cause)
        }
    }

    func review(
        _ records: [JournalDayRecord],
        today: Date,
        workingWeekdays: Set<Weekday> = Self.weekdays,
        format: JournalFormat? = nil
    ) -> JournalYearReview {
        let format = format ?? self.format
        return JournalYearReview(
            records: records,
            period: JournalPeriod.containing(
                day(2026, 6, 1), range: .year, calendar: format.calendar
            ),
            today: today,
            workingWeekdays: workingWeekdays,
            format: format
        )
    }

    func card(_ review: JournalYearReview) throws -> JournalYearReview.Card {
        guard case .card(let card) = review.content else {
            Issue.record("Expected a card, got \(review.content)")
            throw CancellationError()
        }
        return card
    }

    // MARK: - Threshold

    @Test func belowTheThresholdSaysSoInOneLineWithNoCard() {
        let few = records(Array(repeating: -10, count: JournalYearReview.minimumDays - 1))
        let review = review(few, today: day(2026, 3, 1))
        #expect(review.content == .tooFewDays(
            "A time card needs 20 working days. This year has 19."
        ))
        #expect(review.year == 2026)
        #expect(review.placement == .trailing)
    }

    @Test func daysWithoutAStopTimeDoNotCountTowardTheThreshold() {
        let offsets: [Int?] = Array(repeating: -10, count: 19) + Array(repeating: nil, count: 10)
        guard case .tooFewDays = review(records(offsets), today: day(2026, 3, 1)).content else {
            Issue.record("Days without a stop time made the card")
            return
        }
    }

    @Test func theThresholdItselfMakesTheCard() throws {
        let enough = records(Array(repeating: -10, count: JournalYearReview.minimumDays))
        let review = review(enough, today: day(2026, 3, 1))
        _ = try card(review)
        #expect(review.placement == .leading)
    }

    // MARK: - Headlines

    @Test func theDefaultHeadlineCountsEveningsOutBeforeCurfew() throws {
        // 12 early alternating with lock days, then 8 over by 30.
        let offsets: [Int?] = (0 ..< 24).map { $0.isMultiple(of: 2) ? -20 : 0 }
            + Array(repeating: 30, count: 8)
        let card = try card(review(records(offsets), today: day(2027, 1, 10)))
        let headline = card.headline(.eveningsOut)
        #expect(headline.value == "12")
        #expect(headline.unit == nil)
        #expect(headline.line == "evenings out before curfew")
        #expect(headline.spoken == "12 evenings out before curfew.")
        #expect(card.yearLabel == "2026")
    }

    @Test func oneEveningOutIsSingular() throws {
        let offsets: [Int?] = [-20] + Array(repeating: 0, count: 24)
        let card = try card(review(records(offsets), today: day(2027, 1, 10)))
        #expect(card.headline(.eveningsOut).line == "evening out before curfew")
        #expect(card.headline(.longestRun)
            .spoken == "Longest run: 1 evening in a row out before curfew.")
    }

    @Test func theUsualTimeOutIsTheTypicalStopWithItsDayPeriodSetSmall() throws {
        let finished = try card(review(
            records(Array(repeating: -15, count: 25)),
            today: day(2027, 1, 2)
        ))
        let usual = finished.headline(.usualTime)
        #expect(usual.value == "5:45")
        #expect(usual.unit == "PM")
        #expect(usual.line == "was your usual time out")
        #expect(usual.spoken == "5:45 PM was your usual time out.")

        let running = try card(review(
            records(Array(repeating: -15, count: 25)),
            today: day(2026, 3, 1)
        ))
        #expect(running.headline(.usualTime).line == "is your usual time out")
        #expect(running.yearLabel == "2026 so far")
    }

    @Test func aTwentyFourHourClockHasNoDayPeriod() throws {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_GB")
        let format = JournalFormat(calendar: calendar, locale: Locale(identifier: "en_GB"))
        let card = try card(review(
            records(Array(repeating: -15, count: 25)), today: day(2027, 1, 2), format: format
        ))
        #expect(card.headline(.usualTime).value == "17:45")
        #expect(card.headline(.usualTime).unit == nil)
    }

    @Test func theLongestRunCountsEveningsInARow() throws {
        let offsets: [Int?] = Array(repeating: -10, count: 7) + [0] + Array(
            repeating: -10,
            count: 14
        )
        let card = try card(review(records(offsets), today: day(2027, 1, 2)))
        let run = card.headline(.longestRun)
        #expect(run.value == "14")
        #expect(run.line == "in a row out before curfew")
        #expect(run.spoken == "Longest run: 14 evenings in a row out before curfew.")
    }

    // MARK: - Footer

    @Test func theFooterCountsWorkingDaysAndTheEveningsTheLockEnded() throws {
        let offsets: [Int?] = Array(repeating: -10, count: 18) + [0, 0, 0]
            + [nil]
        var days = records(offsets)
        // Over by 20 after an extension, ended by the lock.
        days.append(record(day(2026, 3, 2), offset: 20))
        // Over by 5, called by the person inside an extension.
        days.append(record(day(2026, 3, 3), offset: 5, cause: .calledItADay))
        let card = try card(review(days, today: day(2027, 1, 2)))
        #expect(card.workingDaysLabel == "23 working days")
        #expect(card.lockLabel == "4 ended by the lock")
    }

    @Test func theCardNeverCarriesWrittenWords() throws {
        var days = records(Array(repeating: -10, count: 24))
        days.append(record(
            day(2026, 3, 2),
            offset: 45,
            overrideMinutes: 45,
            reason: "Secret reason"
        ))
        let card = try card(review(days, today: day(2026, 4, 1)))
        var everything = [card.yearLabel, card.workingDaysLabel, card.lockLabel]
        for headline in JournalTimeCardHeadline.allCases {
            let words = card.headline(headline)
            everything += [words.value, words.unit ?? "", words.line, words.spoken]
        }
        for punches in JournalTimeCardPunches.allCases {
            everything.append(card.spokenSummary(
                JournalTimeCardStyle(
                    stock: .night,
                    sky: .sundown,
                    punches: punches,
                    headline: .eveningsOut
                )
            ))
        }
        for text in everything {
            #expect(!text.contains("Secret"))
            #expect(!text.contains("billing"))
        }
    }

    @Test func voiceOverReadsTheHeadlineTheFooterAndThePunches() throws {
        let offsets: [Int?] = Array(repeating: -10, count: 20) + [0, 0]
        let card = try card(review(records(offsets), today: day(2027, 1, 2)))
        let calendarSummary = card.spokenSummary(JournalTimeCardStyle(
            stock: .paper, sky: .desert, punches: .calendar, headline: .eveningsOut
        ))
        #expect(calendarSummary == "Curfew time card for 2026. 20 evenings out before curfew. "
            + "22 working days, 2 ended by the lock. "
            + "Each evening out before curfew is a hole punched in its place in the year.")
        let skylineSummary = card.spokenSummary(JournalTimeCardStyle(
            stock: .paper, sky: .desert, punches: .skyline, headline: .eveningsOut
        ))
        #expect(skylineSummary.hasSuffix(
            "Each evening you stopped yourself is a hole, stacked by how early or late it was. "
                + "Most were 5 to 10 minutes early."
        ))
    }

    // MARK: - Export

    @Test func theExportIsTheCardOnItsStageAtOneSize() {
        #expect(JournalYearReview.exportSize == CGSize(width: 800, height: 1000))
        #expect(JournalYearReview.exportScale == 2)
        #expect(JournalYearReview.fileName(year: 2031) == "curfew-time-card-2031.png")
        #expect(JournalTimeCardLayout.aspectRatio == 8.0 / 11.0)
    }
}

/// Where the card sits on the year page, and the pasteboard it copies to.
extension JournalYearReviewTests {
    // MARK: - Placement

    @Test func onlyTheYearRangeHasTheCard() {
        let days = records(Array(repeating: -10, count: 30))
        for (range, expected) in [(JournalRange.week, false), (.month, false), (.year, true)] {
            let screen = JournalScreen(
                records: days,
                period: JournalPeriod.containing(
                    day(2026, 1, 20),
                    range: range,
                    calendar: calendar
                ),
                today: day(2026, 6, 1),
                workingWeekdays: Self.weekdays,
                format: format
            )
            #expect((screen.yearReview != nil) == expected)
        }
    }

    @Test func aYearWithNoWorkingDaysHasNoCard() {
        let screen = JournalScreen(
            records: records(Array(repeating: -10, count: 30)),
            period: JournalPeriod.containing(day(2025, 6, 1), range: .year, calendar: calendar),
            today: day(2026, 6, 1),
            workingWeekdays: [.monday],
            format: format
        )
        #expect(screen.yearReview == nil)
    }

    @Test func theYearPageLeadsWithTheCardAndATooShortYearEndsWithItsLine() {
        func sections(
            _ days: [JournalDayRecord],
            _ range: JournalRange
        ) -> [JournalScreen.Section] {
            JournalScreen(
                records: days,
                period: JournalPeriod.containing(
                    day(2026, 1, 20),
                    range: range,
                    calendar: calendar
                ),
                today: day(2026, 6, 1),
                workingWeekdays: Self.weekdays,
                format: format
            ).sections
        }
        let days = records(Array(repeating: -10, count: 30))
        #expect(sections(days, .year) == [.yearReview, .summary, .patterns, .words, .days])
        #expect(sections(days, .month) == [.summary, .patterns, .words, .days])
        let few = records(Array(repeating: -10, count: 6))
        #expect(sections(few, .year) == [.summary, .patterns, .words, .days, .yearReview])
    }

    @Test @MainActor func copyReplacesThePasteboardWithThePNG() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("JournalYearReview-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Earlier text", forType: .string)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(JournalYearReviewPasteboard.write(png: png, to: pasteboard))
        #expect(pasteboard.data(forType: .png) == png)
        #expect(pasteboard.string(forType: .string) == nil)
    }
}
