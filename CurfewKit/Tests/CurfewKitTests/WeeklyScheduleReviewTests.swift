@testable import CurfewKit
import Testing

struct WeeklyScheduleReviewTests {
    @Test("Review text includes every effective day and its actual trigger")
    func allSevenRulesAreVisible() {
        var schedule = WeeklySchedule.tenToSix
        schedule.rules[.tuesday] = DayRule(
            isDayOff: false,
            lockMinutes: 21 * 60,
            unlockMinutes: 7 * 60,
            mode: .combined,
            hoursLimitMinutes: 7 * 60
        )

        let lines = schedule.reviewLines

        #expect(lines.count == 7)
        #expect(lines[0].contains("Mon"))
        #expect(lines[0].contains("22:00"))
        #expect(lines[0].contains("06:00"))
        #expect(lines[1].contains("21:00"))
        #expect(lines[1].contains("7 h"))
        #expect(lines[1].contains("07:00"))
        #expect(lines[5].contains("Sat"))
        #expect(lines[5].contains("off"))
        #expect(lines[6].contains("Sun"))
    }
}
