@testable import CurfewKit
import Foundation
import Testing

struct WeeklyScheduleReviewTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    private func normalized(_ lines: [String]) -> [String] {
        lines.map {
            $0.replacingOccurrences(of: "\u{202F}", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }
    }

    @Test("Review text includes every day in the locale's time format")
    func allSevenRulesAreVisible() {
        var schedule = WeeklySchedule.tenToSix
        schedule.rules[.tuesday] = DayRule(
            isDayOff: false,
            lockMinutes: 21 * 60,
            unlockMinutes: 7 * 60,
            mode: .combined,
            hoursLimitMinutes: 7 * 60
        )

        let lines = normalized(schedule.reviewLines(locale: posix))

        #expect(lines.count == 7)
        #expect(lines[0] == "Mon, 10:00 PM to 6:00 AM")
        #expect(lines[1] == "Tue, 9:00 PM or after 7 hours of work, to 7:00 AM")
        #expect(lines[5] == "Sat, day off")
        #expect(lines[6].hasPrefix("Sun"))
    }

    @Test("Review text never prints forced 24-hour times")
    func reviewTextAvoidsTwentyFourHourClock() {
        let lines = normalized(WeeklySchedule.tenToSix.reviewLines(locale: posix))
        #expect(lines.allSatisfy { !$0.contains("22:00") && !$0.contains("locks at") })
    }

    @Test("Hours-only rules describe the work limit")
    func hoursRule() {
        var schedule = WeeklySchedule.tenToSix
        schedule.rules[.monday] = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .hours,
            hoursLimitMinutes: 7 * 60 + 30
        )
        let lines = normalized(schedule.reviewLines(locale: posix))
        #expect(lines[0] == "Mon, after 7 hours 30 minutes of work, to 8:00 AM")
    }

    @Test("A day off tomorrow reads plainly")
    func dayOffSummary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // Friday 2026-02-06; Saturday is a day off in every preset.
        let friday = try #require(calendar.date(from: .init(year: 2026, month: 2, day: 6, hour: 9)))
        let sentence = WeeklySchedule.tenToSix.summarySentence(
            forNextDayFrom: friday,
            calendar: calendar,
            locale: posix
        )
        #expect(sentence == "Tomorrow is a day off. No curfew.")
    }
}
