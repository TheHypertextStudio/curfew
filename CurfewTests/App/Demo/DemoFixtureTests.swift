@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for ``DemoFixture`` — the pure builders that seed demo /
/// marketing capture launches. Debug-only (the type lives behind `#if DEBUG`),
/// which is fine because the test bundle always builds Debug.
@MainActor
struct DemoFixtureTests {
    @Test("Demo settings complete onboarding and disable shutdown + MCP")
    func demoSettingsAreSafe() {
        let settings = DemoFixture.demoSettings()
        #expect(settings.hasCompletedInitialSetup)
        // Auto-shutdown MUST be off so a capture run can never power off the
        // machine — this is the headline safety guarantee of demo mode.
        #expect(settings.autoShutdownEnabled == false)
        #expect(settings.mcpEnabled == false)
        #expect(settings.mcpHTTPEnabled == false)
    }

    @Test("Seeded activity yields a three-day streak, two extensions, one override")
    func seededActivityRollsUpNicely() {
        let calendar = fixedCalendar()
        // A Thursday so the -2/-1/0 day offsets all land in the same week.
        let now = midday(2026, 4, 16)
        let weekStart = midday(2026, 4, 13) // Monday of that week

        let events = DemoFixture.seededActivityEvents(now: now, calendar: calendar)
        let rollup = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: weekStart,
            calendar: calendar
        )

        #expect(rollup.daysWithLockout == 3)
        #expect(rollup.streak == 3)
        #expect(rollup.totalExtensionCount == 2)
        #expect(rollup.totalExtensionMinutes == 30)
        #expect(rollup.totalOverrideCount == 1)
        #expect(rollup.totalOverrideMinutes == 30)
    }

    @Test("Lockout scenario produces a locked evaluation with a later unlock")
    func lockoutEvaluation() {
        let calendar = fixedCalendar()
        let now = midday(2026, 4, 16)
        let evaluation = DemoFixture.evaluation(for: .lockout, now: now, calendar: calendar)

        #expect(evaluation.phase == .locked)
        #expect(evaluation.warningStage == .lockout)
        let lock = try? #require(evaluation.lockDate)
        let unlock = try? #require(evaluation.unlockDate)
        if let lock, let unlock {
            #expect(unlock > lock)
        }
    }

    @Test("Working scenarios show a positive countdown")
    func workingEvaluation() {
        let calendar = fixedCalendar()
        let now = DemoFixture.referenceTime(
            for: .overview,
            now: midday(2026, 4, 16),
            calendar: calendar
        )
        let evaluation = DemoFixture.evaluation(for: .overview, now: now, calendar: calendar)

        #expect(evaluation.phase == .working)
        #expect(evaluation.minutesRemaining > 0)
        #expect(evaluation.minutesRemaining != .max)
    }

    @Test("Reference time pins a flattering wall-clock per scenario")
    func referenceTimePins() {
        let calendar = fixedCalendar()
        let base = midday(2026, 4, 16)

        let lockoutHour = calendar.component(
            .hour,
            from: DemoFixture.referenceTime(for: .lockout, now: base, calendar: calendar)
        )
        let overviewHour = calendar.component(
            .hour,
            from: DemoFixture.referenceTime(for: .overview, now: base, calendar: calendar)
        )

        #expect(lockoutHour == 22)
        #expect(overviewHour == 14)
    }

    @Test("Scenario tokens round-trip through their raw values")
    func scenarioTokens() {
        #expect(DemoScenario(rawValue: "getting-started") == .gettingStarted)
        #expect(DemoScenario(rawValue: "this-week") == .thisWeek)
        #expect(DemoScenario(rawValue: "lockout") == .lockout)
    }

    // MARK: - Helpers

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private func midday(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components) ?? Date()
    }
}
