@testable import Curfew
@testable import CurfewKit
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

    // MARK: - The lock time once the hours are spent

    @Test("Hours mode holds the lock time at the lockout's start while it stays locked")
    func hoursLockTimeHoldsWhileLocked() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.hours)))
        let lockedAt = fixedDate(hour: 10)
        for minutesLater in [0, 1, 30, 240, 479] {
            let eval = engine.evaluate(
                at: lockedAt.addingTimeInterval(TimeInterval(minutesLater * 60)),
                schedule: schedule, extensionMinutesGrantedToday: 0, overrideUntil: nil,
                workedMinutesToday: 480, lockoutStartedAt: lockedAt
            )
            #expect(eval.phase == .locked)
            #expect(eval.lockDate == lockedAt)
            #expect(eval.trigger == .hours)
        }
    }

    @Test("Combined mode holds the hours lock time, past the wall-clock curfew too")
    func combinedLockTimeHoldsWhileLocked() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.combined)))
        let lockedAt = fixedDate(hour: 10)
        for hour in [10, 11, 17, 18, 23] {
            let eval = engine.evaluate(
                at: fixedDate(hour: hour).addingTimeInterval(59),
                schedule: schedule, extensionMinutesGrantedToday: 0, overrideUntil: nil,
                workedMinutesToday: 480, lockoutStartedAt: lockedAt
            )
            #expect(eval.phase == .locked)
            #expect(eval.lockDate == lockedAt)
            #expect(eval.trigger == .hours)
        }
    }

    @Test("A spent budget with no lockout yet locks now, and a later start never delays it")
    func spentBudgetLocksNoLaterThanNow() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.hours)))
        let now = fixedDate(hour: 10)
        for start in [nil, now.addingTimeInterval(600)] {
            let eval = engine.evaluate(
                at: now, schedule: schedule, extensionMinutesGrantedToday: 0,
                overrideUntil: nil, workedMinutesToday: 480, lockoutStartedAt: start
            )
            #expect(eval.phase == .locked)
            #expect(eval.lockDate == now)
        }
    }

    @Test("An extension before the lock moves the hours deadline by the granted minutes")
    func extensionBeforeLockMovesDeadline() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.hours)))
        let now = fixedDate(hour: 10)
        let eval = engine.evaluate(
            at: now, schedule: schedule, extensionMinutesGrantedToday: 15,
            overrideUntil: nil, workedMinutesToday: 470
        )
        #expect(eval.phase == .warning)
        #expect(eval.lockDate == now.addingTimeInterval(25 * 60))
    }

    @Test("An extension during the lock moves the hours deadline by the granted minutes")
    func extensionDuringLockMovesDeadline() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.hours)))
        let lockedAt = fixedDate(hour: 10)
        let now = lockedAt.addingTimeInterval(40 * 60)
        let eval = engine.evaluate(
            at: now, schedule: schedule, extensionMinutesGrantedToday: 15,
            overrideUntil: nil, workedMinutesToday: 480, lockoutStartedAt: lockedAt
        )
        #expect(eval.phase == .warning)
        #expect(eval.lockDate == now.addingTimeInterval(15 * 60))
        #expect(eval.trigger == .hours)
    }

    @Test("Time mode ignores the lockout's start")
    func timeModeIgnoresLockoutStart() {
        let engine = CurfewEnforcementEngine(calendar: utcCalendar)
        let schedule = WeeklySchedule(rules: ruleForAllDays(spentRule(.time)))
        let curfew = fixedDate(hour: 18)
        let eval = engine.evaluate(
            at: fixedDate(hour: 19), schedule: schedule, extensionMinutesGrantedToday: 0,
            overrideUntil: nil, workedMinutesToday: 480,
            lockoutStartedAt: fixedDate(hour: 10)
        )
        #expect(eval.phase == .locked)
        #expect(eval.lockDate == curfew)
        #expect(eval.trigger == .time)
    }

    // MARK: - Fixtures

    /// An 18:00 curfew with an eight-hour budget.
    private func spentRule(_ mode: CurfewMode) -> DayRule {
        DayRule(
            isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 8 * 60,
            mode: mode, hoursLimitMinutes: mode == .time ? nil : 480
        )
    }

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
