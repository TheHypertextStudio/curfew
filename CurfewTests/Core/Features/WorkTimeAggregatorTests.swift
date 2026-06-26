@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Covers the active-minutes-today math `WorkTimeAggregator` feeds into
/// the engine when a day rule is in `.hours` or `.combined` mode.
struct WorkTimeAggregatorTests {
    @Test("Empty input returns elapsed minutes since start of day")
    func elapsedMinutesFromStartOfDay() {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: now)
        let minutes = WorkTimeAggregator.activeMinutesToday(
            now: startOfDay.addingTimeInterval(90 * 60), // 90 minutes later
            events: [],
            calendar: calendar
        )
        #expect(minutes == 90)
    }

    @Test("Idle windows subtract when they exceed the 5-minute threshold")
    func idleAboveThresholdSubtracts() {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: now)
        let evaluateAt = startOfDay.addingTimeInterval(60 * 60) // 60 min in
        let idleStart = startOfDay.addingTimeInterval(10 * 60)
        let idleEnd = startOfDay.addingTimeInterval(25 * 60) // 15-min idle window

        let minutes = WorkTimeAggregator.activeMinutesToday(
            now: evaluateAt,
            events: [],
            idleWindows: [idleStart ..< idleEnd],
            calendar: calendar
        )
        #expect(minutes == 60 - 15)
    }

    @Test("Idle windows below threshold are ignored")
    func idleBelowThresholdIgnored() {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: now)
        let evaluateAt = startOfDay.addingTimeInterval(60 * 60)
        let idleStart = startOfDay.addingTimeInterval(10 * 60)
        let idleEnd = startOfDay.addingTimeInterval(12 * 60) // 2-min idle, < 5 min cutoff

        let minutes = WorkTimeAggregator.activeMinutesToday(
            now: evaluateAt,
            events: [],
            idleWindows: [idleStart ..< idleEnd],
            calendar: calendar
        )
        #expect(minutes == 60)
    }

    @Test("Lockout intervals subtract from active time")
    func lockoutSubtracts() {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: now)
        let evaluateAt = startOfDay.addingTimeInterval(60 * 60)
        let lockoutStart = startOfDay.addingTimeInterval(20 * 60)
        let lockoutEnd = startOfDay.addingTimeInterval(30 * 60)

        let events: [ActivityEvent] = [
            ActivityEvent(
                timestamp: lockoutStart,
                gateKind: GateKind.curfew,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            ),
            ActivityEvent(
                timestamp: lockoutEnd,
                gateKind: GateKind.curfew,
                kind: .lockoutEnded,
                minutesValue: nil,
                note: nil
            )
        ]

        let minutes = WorkTimeAggregator.activeMinutesToday(
            now: evaluateAt,
            events: events,
            calendar: calendar
        )
        #expect(minutes == 50)
    }

    @Test("Lockout longer than elapsed clamps to zero, never negative")
    func lockoutLongerThanElapsedClampsToZero() {
        let calendar = utcCalendar
        let startOfDay = calendar.startOfDay(for: now)
        // Evaluate 30 min in, with a lockout covering the whole window.
        let evaluateAt = startOfDay.addingTimeInterval(30 * 60)
        let events: [ActivityEvent] = [
            ActivityEvent(
                timestamp: startOfDay,
                gateKind: GateKind.curfew,
                kind: .lockoutStarted,
                minutesValue: nil,
                note: nil
            )
        ]
        let minutes = WorkTimeAggregator.activeMinutesToday(
            now: evaluateAt,
            events: events,
            calendar: calendar
        )
        #expect(minutes == 0)
    }

    // MARK: - Fixtures

    private var now: Date {
        // Mid-afternoon, so start-of-day exercise is meaningful.
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 15
        components.hour = 14
        components.minute = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: components) ?? Date()
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
}
