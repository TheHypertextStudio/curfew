@testable import Curfew
import Foundation
import Testing

/// Engine behaviour under the new `.hours` and `.combined` curfew modes.
/// Pins a fixed `Date` + `Calendar` for determinism — DST / timezone
/// drift is exercised in `ScheduleResolutionTests`, not here.
@MainActor
struct HoursModeEngineTests {
    @Test("Hours mode locks once workedMinutesToday exceeds the limit")
    func hoursModeLocksAtLimit() {
        let rule = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .hours,
            hoursLimitMinutes: 480 // 8h
        )
        let schedule = WeeklySchedule(rules: ruleForAllDays(rule))
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let now = fixedDate(hour: 10)

        // 480 min of work already accumulated → hoursDeadline == now → locked.
        let eval = engine.evaluate(
            at: now,
            schedule: schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: .default,
            workedMinutesToday: 480
        )
        #expect(eval.phase == .locked)
        #expect(eval.trigger == .hours)
    }

    @Test("Hours mode still working when under the limit")
    func hoursModeWorkingUnderLimit() {
        let rule = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .hours,
            hoursLimitMinutes: 480
        )
        let schedule = WeeklySchedule(rules: ruleForAllDays(rule))
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let now = fixedDate(hour: 10)
        let eval = engine.evaluate(
            at: now,
            schedule: schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: .default,
            workedMinutesToday: 120 // 2h in
        )
        #expect(eval.phase == .working)
        #expect(eval.trigger == .hours)
    }

    @Test("Combined mode picks the earlier of time and hours deadlines")
    func combinedModeEarlierDeadlineWins() {
        // 18:00 wall time vs. hours exhausted at 11:00 (now=10:45,
        // workedMinutes means 15 minutes of budget remain). Hours wins.
        let rule = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .combined,
            hoursLimitMinutes: 360 // 6h
        )
        let schedule = WeeklySchedule(rules: ruleForAllDays(rule))
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        var nowComponents = DateComponents()
        nowComponents.year = 2026
        nowComponents.month = 4
        nowComponents.day = 15
        nowComponents.hour = 10
        nowComponents.minute = 45
        nowComponents.timeZone = TimeZone(identifier: "UTC")
        let now = utcCalendar.date(from: nowComponents) ?? Date()
        let eval = engine.evaluate(
            at: now,
            schedule: schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: .default,
            workedMinutesToday: 360 - 15 // 15 min of budget left
        )
        #expect(eval.phase == .warning)
        #expect(eval.trigger == .hours)
    }

    @Test("Time mode ignores workedMinutesToday")
    func timeModeIgnoresWorkedMinutes() {
        let rule = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60
        )
        let schedule = WeeklySchedule(rules: ruleForAllDays(rule))
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let now = fixedDate(hour: 10)
        let eval = engine.evaluate(
            at: now,
            schedule: schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: .default,
            workedMinutesToday: 10000 // absurd — time-mode should ignore
        )
        #expect(eval.phase == .working)
        #expect(eval.trigger == .time)
    }

    // MARK: - Fixtures

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func fixedDate(hour: Int) -> Date {
        // 2026-04-15 (Wednesday) so the engine picks a weekday rule.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 15
        components.hour = hour
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components) ?? Date()
    }

    private func ruleForAllDays(_ rule: DayRule) -> [Weekday: DayRule] {
        Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0, rule) })
    }
}
