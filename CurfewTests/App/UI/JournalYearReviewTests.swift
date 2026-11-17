import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The year in review card's words, threshold, marks and file name, built
/// from day records without any view.
struct JournalYearReviewTests {
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

    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// A day that ended `offset` minutes from a 6:00 PM curfew.
    func record(
        _ date: Date,
        offset: Int?,
        done: Bool? = true,
        overrideMinutes: Int = 0,
        reason: String? = nil
    ) -> JournalDayRecord {
        let curfew = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date)!
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
            overrideMinutes: overrideMinutes,
            overrideReasons: reason.map { [$0] } ?? [],
            oneThing: "Ship the private billing migration",
            oneThingDone: done
        )
    }

    /// `offsets` on consecutive days from Jan 5, 2026.
    func records(_ offsets: [Int?]) -> [JournalDayRecord] {
        offsets.enumerated().map { index, offset in
            record(
                calendar.date(byAdding: .day, value: index, to: day(2026, 1, 5))!,
                offset: offset,
                done: index.isMultiple(of: 2)
            )
        }
    }

    func review(_ records: [JournalDayRecord], today: Date) -> JournalYearReview {
        JournalYearReview(
            records: records,
            period: JournalPeriod.containing(day(2026, 6, 1), range: .year, calendar: calendar),
            today: today,
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
            "A year in review needs 20 working days. This year has 19."
        ))
        #expect(review.year == 2026)
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
        _ = try card(review(enough, today: day(2026, 3, 1)))
    }

    // MARK: - Words

    @Test func aFinishedYearUsesThePrototypeWording() throws {
        // 12 early (alternating with lock days), then 8 over by 30.
        let offsets: [Int?] = (0 ..< 24).map { $0.isMultiple(of: 2) ? -20 : 0 }
            + Array(repeating: 30, count: 8)
        let card = try card(review(records(offsets), today: day(2027, 1, 10)))
        #expect(card.yearLabel == "2026")
        #expect(card.headline == "12 evenings ended before curfew.")
        #expect(card.totals.map(\.label) == [
            "typical stop", "you did the one thing", "extra time, all year",
            "longest run stopping early"
        ])
        #expect(card.totals[0].value == "6:00 PM")
        #expect(card.totals[1].value == "16 days")
        #expect(card.totals[2].value == "4h")
        #expect(card.totals[3].value == "1 day")
        #expect(card.fileName == "curfew-year-in-review-2026.png")
    }

    @Test func aYearStillRunningSaysSoFar() throws {
        let card = try card(review(
            records(Array(repeating: -15, count: 25)),
            today: day(2026, 3, 1)
        ))
        #expect(card.yearLabel == "2026 so far")
        #expect(card.totals[2].label == "extra time so far")
        #expect(card.totals[0].value == "5:45 PM")
        #expect(card.totals[3].value == "25 days")
    }

    @Test func headlineCountsAreWorded() {
        #expect(JournalYearReview.headline(early: 0) == "No evening ended before curfew.")
        #expect(JournalYearReview.headline(early: 1) == "1 evening ended before curfew.")
        #expect(JournalYearReview.headline(early: 127) == "127 evenings ended before curfew.")
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
        let everything = [card.yearLabel, card.headline, card.marksSummary, card.accessibilityValue]
            + card.totals.flatMap { [$0.value, $0.label, $0.spoken] }
        for text in everything {
            #expect(!text.contains("Secret"))
            #expect(!text.contains("billing"))
        }
    }

    @Test func voiceOverReadsTheTotalsAndTheMarks() throws {
        let offsets: [Int?] = Array(repeating: -10, count: 20) + [0, 0, 30]
        let card = try card(review(records(offsets), today: day(2027, 1, 2)))
        #expect(card.marksSummary == "Each working day is a mark on the curfew line: "
            + "20 rise above it for stopping early, 2 sit on it where the lock ended the day, "
            + "1 drop below it for running over.")
        #expect(card.accessibilityValue.hasPrefix("20 evenings ended before curfew. Typical stop"))
        #expect(card.accessibilityValue.contains("You did the one thing on 12 days."))
        #expect(card.accessibilityValue.contains("30m extra time all year."))
        #expect(card.accessibilityValue.contains("Longest run stopping early: 20 days."))
    }

    @Test func marksSummaryLeavesOutKindsThatDidNotHappen() {
        let marks = JournalYearMark.marks(offsets: [-5, -10])
        #expect(JournalYearReview.marksSummary(marks)
            == "Each working day is a mark on the curfew line: 2 rise above it for stopping early.")
    }

    // MARK: - Marks

    @Test func marksGoUpForEarlyDownForOverAndAcrossForTheLock() {
        let marks = JournalYearMark.marks(offsets: [-30, 0, 20])
        let line = JournalYearMark.lineY
        #expect(marks.map(\.kind) == [.early, .atCurfew, .over])
        #expect(marks[0].bottom == line)
        #expect(abs(marks[0].top - (line - 30 * JournalYearMark.lengthPerMinute)) < 1e-9)
        #expect(marks[1].top < line && marks[1].bottom > line)
        #expect(marks[2].top == line)
        #expect(abs(marks[2].bottom - (line + 20 * JournalYearMark.lengthPerMinute)) < 1e-9)
    }

    @Test func earlyAndOverShareOneScale() {
        let marks = JournalYearMark.marks(offsets: [-25, 25])
        let rise = marks[0].bottom - marks[0].top
        let drop = marks[1].bottom - marks[1].top
        #expect(abs(rise - drop) < 1e-9)
    }

    @Test func longStrokesStopShortOfTheWords() {
        let marks = JournalYearMark.marks(offsets: [-500, 500])
        let line = JournalYearMark.lineY
        let per = JournalYearMark.lengthPerMinute
        #expect(abs(marks[0].top - (line - Double(JournalYearMark.earliestMinutes) * per)) < 1e-9)
        #expect(abs(marks[1].bottom - (line + Double(JournalYearMark.latestMinutes) * per)) < 1e-9)
        // The totals start about 15% above the bottom edge.
        #expect(marks[1].bottom < 0.85)
        // The headline ends about a third of the way down.
        #expect(marks[0].top > 0.4)
    }

    @Test func marksAreSpacedEvenlyAlongTheLine() {
        let marks = JournalYearMark.marks(offsets: [-1, -1, -1, -1])
        let slot = (JournalYearMark.lineEnd - JournalYearMark.lineStart) / 4
        #expect(abs(marks[0].centerX - (JournalYearMark.lineStart + slot / 2)) < 1e-9)
        #expect(abs(marks[3].centerX - (JournalYearMark.lineEnd - slot / 2)) < 1e-9)
    }

    @Test func theCardDrawsOnlyDaysWithAStopTimeInDayOrder() throws {
        let offsets: [Int?] = [nil] + Array(repeating: -10, count: 20) + [nil, 15]
        let card = try card(review(records(offsets).shuffled(), today: day(2026, 3, 1)))
        #expect(card.marks.count == 21)
        #expect(card.marks.last?.kind == .over)
    }

    @Test func strokesThinWithMoreDaysButNeverVanish() {
        #expect(JournalYearMark.strokeWidth(count: 10, width: 1600) > JournalYearMark.strokeWidth(
            count: 250, width: 1600
        ))
        #expect(JournalYearMark.strokeWidth(count: 5000, width: 300) == 1)
    }

    // MARK: - Export and placement

    @Test func theExportIsOneFixedSize() {
        #expect(JournalYearReview.exportSize == CGSize(width: 1600, height: 1000))
        #expect(JournalYearReview.exportScale == 2)
        #expect(JournalYearReview.fileName(year: 2031) == "curfew-year-in-review-2031.png")
    }

    @Test func onlyTheYearRangeEndsWithTheCard() {
        let days = records(Array(repeating: -10, count: 30))
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        for (range, expected) in [(JournalRange.week, false), (.month, false), (.year, true)] {
            let screen = JournalScreen(
                records: days,
                period: JournalPeriod.containing(
                    day(2026, 1, 20),
                    range: range,
                    calendar: calendar
                ),
                today: day(2026, 6, 1),
                workingWeekdays: weekdays,
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
}

/// Where the card sits on the page, and what Copy and Save say and do.
extension JournalYearReviewTests {
    // MARK: - Section order

    @Test func theYearPageLeadsWithTheCardAndOtherRangesHaveNone() {
        let days = records(Array(repeating: -10, count: 30))
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        func sections(_ range: JournalRange) -> [JournalScreen.Section] {
            JournalScreen(
                records: days,
                period: JournalPeriod.containing(
                    day(2026, 1, 20),
                    range: range,
                    calendar: calendar
                ),
                today: day(2026, 6, 1),
                workingWeekdays: weekdays,
                format: format
            ).sections
        }
        #expect(sections(.year) == [.yearReview, .summary, .patterns, .words, .days])
        #expect(sections(.month) == [.summary, .patterns, .words, .days])
        #expect(sections(.week) == [.summary, .patterns, .words, .days])
    }

    @Test func aYearWithTooFewDaysEndsThePageWithItsOneLine() {
        let few = records(Array(repeating: -10, count: 6))
        #expect(review(few, today: day(2026, 3, 1)).placement == .trailing)
        let screen = JournalScreen(
            records: few,
            period: JournalPeriod.containing(day(2026, 1, 20), range: .year, calendar: calendar),
            today: day(2026, 6, 1),
            workingWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            format: format
        )
        #expect(screen.sections == [.summary, .patterns, .words, .days, .yearReview])
    }

    // MARK: - Copy and Save

    @Test func copySaysItIsWorkingThenConfirmsInItsOwnLabel() {
        #expect(JournalYearReviewWork.idle.copyTitle == "Copy image")
        #expect(JournalYearReviewWork.copying.copyTitle == "Copying…")
        #expect(JournalYearReviewWork.copied.copyTitle == "Copied")
        #expect(JournalYearReviewWork.copied.copySymbol == "checkmark")
        #expect(JournalYearReviewWork.idle.saveTitle == "Save image…")
        #expect(JournalYearReviewWork.saving.saveTitle == "Saving…")
    }

    @Test func copyAndSaveWaitOnlyWhileTheImageRenders() {
        #expect(JournalYearReviewWork.copying.isRendering)
        #expect(JournalYearReviewWork.saving.isRendering)
        #expect(!JournalYearReviewWork.copied.isRendering)
        #expect(!JournalYearReviewWork.idle.isRendering)
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
