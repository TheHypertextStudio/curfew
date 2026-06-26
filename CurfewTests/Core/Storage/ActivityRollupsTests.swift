@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for `ActivityRollups` — the pure aggregation over
/// `[ActivityEvent]` that powers the "This Week" retrospective surface.
@MainActor
struct ActivityRollupsTests {
    @Test("Empty input yields a zero rollup")
    func emptyRollup() {
        let week = ActivityRollups.weeklyRollup(
            events: [],
            weekStart: day(2026, 4, 13),
            calendar: fixedCalendar()
        )
        #expect(week.totalExtensionCount == 0)
        #expect(week.totalOverrideCount == 0)
        #expect(week.daysWithLockout == 0)
        #expect(week.streak == 0)
    }

    @Test("Events are bucketed by day")
    func dayBucketing() {
        let calendar = fixedCalendar()
        let monday = day(2026, 4, 13)
        let wednesday = day(2026, 4, 15)
        let events: [ActivityEvent] = [
            grant(.extensionGranted, minutes: 15, on: monday),
            grant(.extensionGranted, minutes: 15, on: monday),
            grant(.overrideGranted, minutes: 30, on: wednesday, reason: "bug"),
            grant(.lockoutStarted, on: wednesday)
        ]

        let week = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: monday,
            calendar: calendar
        )

        #expect(week.totalExtensionCount == 2)
        #expect(week.totalExtensionMinutes == 30)
        #expect(week.totalOverrideCount == 1)
        #expect(week.totalOverrideMinutes == 30)
        #expect(week.daysWithLockout == 1)

        let mondayRollup = week.days.first { calendar.isDate($0.day, inSameDayAs: monday) }
        #expect(mondayRollup?.extensionCount == 2)
        #expect(mondayRollup?.extensionMinutes == 30)
    }

    @Test("Streak counts consecutive trailing days with lockoutStarted")
    func streakCalculation() {
        let calendar = fixedCalendar()
        let monday = day(2026, 4, 13)
        let events: [ActivityEvent] = [
            grant(.lockoutStarted, on: monday),
            // Tuesday missing → breaks earlier potential streak
            grant(.lockoutStarted, on: day(2026, 4, 15)),
            grant(.lockoutStarted, on: day(2026, 4, 16)),
            grant(.lockoutStarted, on: day(2026, 4, 17))
        ]

        let week = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: monday,
            calendar: calendar
        )

        #expect(week.daysWithLockout == 4)
        // Trailing streak = Wed, Thu, Fri (3) because Friday is the latest
        // day with a lockout relative to weekStart-anchored iteration.
        #expect(week.streak == 3)
    }

    @Test("Events outside the week are ignored")
    func outOfWeekExcluded() {
        let calendar = fixedCalendar()
        let monday = day(2026, 4, 13)
        let priorSunday = day(2026, 4, 12)

        let events: [ActivityEvent] = [
            grant(.extensionGranted, minutes: 15, on: priorSunday),
            grant(.extensionGranted, minutes: 15, on: monday)
        ]

        let week = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: monday,
            calendar: calendar
        )
        #expect(week.totalExtensionCount == 1)
    }

    // MARK: - Helpers

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12 // midday, so timezone quirks don't push us to prior day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components) ?? Date()
    }

    private func grant(
        _ kind: ActivityEventKind,
        minutes: Int? = nil,
        on date: Date,
        reason: String? = nil
    ) -> ActivityEvent {
        ActivityEvent(
            timestamp: date,
            gateKind: GateKind.curfew,
            kind: kind,
            minutesValue: minutes,
            note: reason
        )
    }
}
