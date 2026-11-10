@testable import CurfewKit
import Foundation
import Testing

/// Source-only contracts: not yet executed against the inert presentation scaffold.
/// These schedules require neither restriction records nor native power operations.
struct SunrisePresentationPlanTests {
    private let owner = "studio.hypertext.curfew.dev.sunrise"

    private func calendar(_ zone: String = "America/Los_Angeles") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func appearance(lead: Int = 30, battery: Bool = false) -> RestAppearancePreferences {
        RestAppearancePreferences(
            sunriseWakeEnabled: true,
            sunriseLeadMinutes: lead,
            sunriseOnBatteryEnabled: battery
        )
    }

    @Test("Sunrise is disabled by default and an all-days-off schedule has no occurrence")
    func disabledAndDaysOff() {
        let planner = SunriseWakePlanner(owner: owner)
        let now = date("2026-10-19T12:00:00-07:00")
        #expect(planner.presentationPlan(
            schedule: .tenToSix, appearance: .init(), at: now, calendar: calendar()
        ) == nil)
        #expect(planner.presentationPlan(
            schedule: .allDaysOff, appearance: appearance(), at: now, calendar: calendar()
        ) == nil)
    }

    @Test("A future configured night resolves without a restriction or battery-power input")
    func futureOccurrence() throws {
        let plan = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
            schedule: .tenToSix,
            appearance: appearance(),
            at: date("2026-10-19T12:00:00-07:00"),
            calendar: calendar()
        ))
        #expect(plan.owner == owner)
        #expect(plan.wakeAt == date("2026-10-20T05:30:00-07:00"))
        #expect(plan.holdUntil == date("2026-10-20T06:05:00-07:00"))
        #expect(!plan.allowsBattery)
    }

    @Test("Resume retains the same occurrence across midnight, Sunrise, and the display hold")
    func resumeAndHold() throws {
        let planner = SunriseWakePlanner(owner: owner)
        let first = try #require(planner.presentationPlan(
            schedule: .tenToSix, appearance: appearance(),
            at: date("2026-10-19T23:59:00-07:00"), calendar: calendar()
        ))
        for instant in [
            "2026-10-20T00:01:00-07:00",
            "2026-10-20T05:30:00-07:00",
            "2026-10-20T05:59:00-07:00",
            "2026-10-20T06:00:00-07:00",
            "2026-10-20T06:04:59-07:00"
        ] {
            let resumed = try #require(planner.presentationPlan(
                schedule: .tenToSix, appearance: appearance(),
                at: date(instant), calendar: calendar()
            ))
            #expect(resumed == first)
        }
        let next = try #require(planner.presentationPlan(
            schedule: .tenToSix, appearance: appearance(),
            at: date("2026-10-20T06:05:00-07:00"), calendar: calendar()
        ))
        #expect(next.occurrenceID != first.occurrenceID)
        #expect(next.wakeAt == date("2026-10-21T05:30:00-07:00"))
    }

    @Test("The next configured night is found across days off and a whole weekly cycle")
    func searchesConfiguredNights() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.monday] = DayRule(
            isDayOff: false, lockMinutes: 22 * 60, unlockMinutes: 6 * 60
        )
        let plan = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
            schedule: schedule, appearance: appearance(),
            at: date("2026-10-20T06:05:00-07:00"), calendar: calendar()
        ))
        #expect(plan.wakeAt == date("2026-10-27T05:30:00-07:00"))
    }

    @Test("Identity survives recreation, ticks, lead changes, and battery preference changes")
    func stableIdentity() throws {
        let now = date("2026-10-19T12:00:00-07:00")
        let first = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
            schedule: .tenToSix, appearance: appearance(), at: now, calendar: calendar()
        ))
        for lead in [5, 15, 60] {
            let recreated = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
                schedule: .tenToSix, appearance: appearance(lead: lead, battery: true),
                at: now.addingTimeInterval(60), calendar: calendar()
            ))
            #expect(recreated.occurrenceID == first.occurrenceID)
            #expect(recreated.wakeAt == date("2026-10-20T06:00:00-07:00")
                .addingTimeInterval(-Double(lead * 60)))
            #expect(recreated.allowsBattery)
        }
    }

    @Test("Identity follows the owner and absolute window across timezone reconciliation")
    func distinctIdentity() throws {
        let now = date("2026-10-19T12:00:00-07:00")
        let planner = SunriseWakePlanner(owner: owner)
        let first = try #require(planner.presentationPlan(
            schedule: .tenToSix, appearance: appearance(), at: now, calendar: calendar()
        ))
        var changed = WeeklySchedule.tenToSix
        changed.rules[.monday] = DayRule(
            isDayOff: false, lockMinutes: 21 * 60, unlockMinutes: 6 * 60
        )
        let changedWindow = try #require(planner.presentationPlan(
            schedule: changed, appearance: appearance(), at: now, calendar: calendar()
        ))
        let changedOwner = try #require(SunriseWakePlanner(owner: "another.sunrise")
            .presentationPlan(
                schedule: .tenToSix,
                appearance: appearance(),
                at: now,
                calendar: calendar()
            ))
        let equivalentZone = try #require(planner.presentationPlan(
            schedule: .tenToSix, appearance: appearance(), at: now,
            calendar: calendar("America/Vancouver")
        ))
        let changedZone = try #require(planner.presentationPlan(
            schedule: .tenToSix, appearance: appearance(), at: now,
            calendar: calendar("America/New_York")
        ))
        #expect(changedWindow.occurrenceID != first.occurrenceID)
        #expect(changedOwner.occurrenceID != first.occurrenceID)
        #expect(equivalentZone.wakeAt == first.wakeAt)
        #expect(equivalentZone.holdUntil == first.holdUntil)
        #expect(equivalentZone.occurrenceID == first.occurrenceID)
        #expect(changedZone.wakeAt != first.wakeAt)
        #expect(changedZone.occurrenceID != first.occurrenceID)
    }

    @Test("Presentation consumes the normalized lead preference", arguments: [-20, 200])
    func normalizedLead(raw: Int) throws {
        let preferences = appearance(lead: raw)
        let plan = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
            schedule: .tenToSix, appearance: preferences,
            at: date("2026-10-19T12:00:00-07:00"), calendar: calendar()
        ))
        #expect(plan.wakeAt == date("2026-10-20T06:00:00-07:00")
            .addingTimeInterval(-Double(preferences.sunriseLeadMinutes * 60)))
    }

    @Test("Transition-day lock and next-day unlock preserve their configured local times")
    func configuredUnlockPreservesWallClockAcrossDST() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.sunday] = DayRule(
            isDayOff: false, lockMinutes: 22 * 60, unlockMinutes: 6 * 60
        )
        for (instant, lock, unlock) in [
            ("2026-03-08T12:00:00-07:00", "2026-03-08T22:00:00-07:00", "2026-03-09T06:00:00-07:00"),
            ("2026-11-01T12:00:00-08:00", "2026-11-01T22:00:00-08:00", "2026-11-02T06:00:00-08:00")
        ] {
            let window = try #require(schedule.scheduleWindow(
                for: date(instant), calendar: calendar()
            ))
            #expect(window.lockDate == date(lock))
            #expect(window.unlockDate == date(unlock))
        }
    }

    @Test("Presentation and enforcement use the same resolved DST occurrence")
    func daylightSavingWindows() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.sunday] = DayRule(
            isDayOff: false, lockMinutes: 22 * 60, unlockMinutes: 6 * 60
        )
        for instant in [
            "2026-03-08T12:00:00-07:00",
            "2026-11-01T12:00:00-08:00"
        ] {
            let window = try #require(schedule.scheduleWindow(
                for: date(instant), calendar: calendar()
            ))
            let plan = try #require(SunriseWakePlanner(owner: owner).presentationPlan(
                schedule: schedule, appearance: appearance(),
                at: date(instant), calendar: calendar()
            ))
            #expect(plan.wakeAt == window.unlockDate.addingTimeInterval(-1800))
            #expect(plan.holdUntil == window.unlockDate.addingTimeInterval(300))
        }
    }

    @Test("An overnight unlock on the transition day preserves its configured local clock")
    func overnightTransitionUnlock() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.saturday] = DayRule(
            isDayOff: false, lockMinutes: 22 * 60, unlockMinutes: 6 * 60
        )
        for (instant, unlock) in [
            ("2026-03-07T12:00:00-08:00", "2026-03-08T06:00:00-07:00"),
            ("2026-10-31T12:00:00-07:00", "2026-11-01T06:00:00-08:00")
        ] {
            let window = try #require(schedule.scheduleWindow(
                for: date(instant), calendar: calendar()
            ))
            #expect(window.unlockDate == date(unlock))
        }
    }

    @Test("A same-day unlock on the transition day preserves its configured local clock")
    func sameDayTransitionUnlock() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.sunday] = DayRule(
            isDayOff: false, lockMinutes: 6 * 60, unlockMinutes: 8 * 60
        )
        for (instant, lock, unlock) in [
            ("2026-03-08T00:00:00-08:00", "2026-03-08T06:00:00-07:00", "2026-03-08T08:00:00-07:00"),
            ("2026-11-01T00:00:00-07:00", "2026-11-01T06:00:00-08:00", "2026-11-01T08:00:00-08:00")
        ] {
            let window = try #require(schedule.scheduleWindow(
                for: date(instant), calendar: calendar()
            ))
            #expect(window.lockDate == date(lock))
            #expect(window.unlockDate == date(unlock))
        }
    }

    @Test("An elapsed extension crossing the spring gap rolls past an earlier unlock clock")
    func springExtensionRollover() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.sunday] = DayRule(
            isDayOff: false, lockMinutes: 90, unlockMinutes: 180
        )
        let window = try #require(schedule.scheduleWindow(
            for: date("2026-03-08T00:00:00-08:00"),
            extensionMinutesGrantedToday: 60, calendar: calendar()
        ))
        #expect(window.lockDate == date("2026-03-08T03:30:00-07:00"))
        #expect(window.unlockDate == date("2026-03-09T03:00:00-07:00"))
        #expect(window.unlockDate > window.lockDate)
    }

    @Test("A fallback daytime window never collapses its lock and unlock to the same instant")
    func fallDaytimeWindow() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.sunday] = DayRule(
            isDayOff: false, lockMinutes: 360, unlockMinutes: 420
        )
        let window = try #require(schedule.scheduleWindow(
            for: date("2026-11-01T00:00:00-07:00"), calendar: calendar()
        ))
        #expect(window.lockDate == date("2026-11-01T06:00:00-08:00"))
        #expect(window.unlockDate == date("2026-11-01T07:00:00-08:00"))
        #expect(window.unlockDate > window.lockDate)
    }
}

extension SunrisePresentationPlanTests {
    @Test("Saved explicit next-day offsets retain their original calendar reference")
    func explicitDayOffsets() throws {
        var schedule = WeeklySchedule.allDaysOff
        schedule.rules[.monday] = DayRule(
            isDayOff: false, lockMinutes: 26 * 60, unlockMinutes: 32 * 60
        )
        let window = try #require(schedule.scheduleWindow(
            for: date("2026-10-19T12:00:00-07:00"), calendar: calendar()
        ))
        #expect(window.lockDate == date("2026-10-20T02:00:00-07:00"))
        #expect(window.unlockDate == date("2026-10-20T08:00:00-07:00"))
    }
}
