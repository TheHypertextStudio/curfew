@testable import Curfew
import Foundation
import Testing

struct CurfewEnforcementEngineTests {
    @Test("Working state before warning window")
    func workingStateBeforeWarning() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 16,
            minute: 0
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .working)
        #expect(state.minutesRemaining == 120)
    }

    @Test("Warning phase starts at T-30")
    func warningAtThirty() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 17,
            minute: 30
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .warning)
        #expect(state.warningStage == .thirtyMinutes)
        #expect(state.canRequestExtension)
    }

    @Test("Lockout begins at curfew")
    func lockoutAtCurfew() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 18,
            minute: 0
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .locked)
        #expect(!state.canRequestExtension)
    }

    @Test("Day off bypasses enforcement")
    func dayOffState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 1,
            hour: 18,
            minute: 0
        ))) // Sunday

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .dayOff)
        #expect(!state.canRequestExtension)
    }

    @Test("Custom warning intervals are respected by enforcement evaluation")
    func customWarningIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let intervals = WarningIntervals(
            thirtyMinutes: 40,
            fifteenMinutes: 25,
            fiveMinutes: 10,
            twoMinutes: 4,
            oneMinute: 1
        )
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 17,
            minute: 52
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: intervals
        )

        #expect(state.warningStage == .fiveMinutes)
        #expect(!state.canRequestExtension)
    }

    @Test("Extensions available only in T-30 and T-15 stages with custom intervals")
    func extensionAvailabilityForCustomIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let intervals = WarningIntervals(
            thirtyMinutes: 40,
            fifteenMinutes: 25,
            fiveMinutes: 10,
            twoMinutes: 4,
            oneMinute: 1
        )
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 17,
            minute: 38
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: intervals
        )

        #expect(state.warningStage == .fifteenMinutes)
        #expect(state.canRequestExtension)
    }

    @Test("Overnight schedule remains locked after midnight")
    func overnightWindowRemainsLockedAfterMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 3,
            hour: 1,
            minute: 0
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .locked)
        #expect(state.unlockDate != nil)
    }

    @Test("Previous-day overnight lock still applies when current day is marked day off")
    func previousOvernightLockAppliesOnCurrentDayOff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        var schedule = WeeklySchedule.standardNineToFive
        schedule.rules[.tuesday] = DayRule(
            isDayOff: true,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60
        )

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 3,
            hour: 1,
            minute: 0
        )))

        let state = engine.evaluate(
            at: date,
            schedule: schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .locked)
    }

    @Test("Less-than-one-minute remaining time does not trigger lockout early")
    func subMinuteRemainingDoesNotLockEarly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let engine = CurfewEnforcementEngine(calendar: calendar)
        let date = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 17,
            minute: 59,
            second: 1
        )))

        let state = engine.evaluate(
            at: date,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil
        )

        #expect(state.phase == .warning)
        #expect(state.minutesRemaining == 1)
    }
}
