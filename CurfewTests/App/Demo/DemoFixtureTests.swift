import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// Behaviour tests for ``DemoFixture`` — the pure builders that seed demo /
/// marketing capture launches. Debug-only (the type lives behind `#if DEBUG`),
/// which is fine because the test bundle always builds Debug.
@MainActor
struct DemoFixtureTests {
    @Test("Activation preserves synthetic permission and keyboard failure captures", arguments: [
        DemoReviewState.accessibilityDenied, .tapDown
    ])
    func activationPreservesVisualHealth(review: DemoReviewState) {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(review)
        let health = model.enforcementHealth
        let trusted = model.isAccessibilityTrusted
        let delegate = AppDelegate()
        delegate.model = model
        delegate.applicationDidBecomeActive(Notification(
            name: NSApplication.didBecomeActiveNotification
        ))
        #expect(model.enforcementHealth == health)
        #expect(model.isAccessibilityTrusted == trusted)
    }

    @Test("Background acceptance still refreshes permission on activation")
    func backgroundActivationRefreshesHealth() {
        let model = CurfewAppModel.demoModel(backgroundEnforcement: true)
        model.isAccessibilityTrusted = false
        model.enforcementHealth = .degradedNoAccessibility
        let delegate = AppDelegate()
        delegate.model = model
        delegate.applicationDidBecomeActive(Notification(
            name: NSApplication.didBecomeActiveNotification
        ))
        #expect(model.isAccessibilityTrusted)
        #expect(model.enforcementHealth != .degradedNoAccessibility)
    }

    @Test("The background fixture starts the real enforcement loop with isolated stores")
    func backgroundFixtureArmsEnforcement() {
        let model = CurfewAppModel.demoModel(backgroundEnforcement: true)
        model.applyDemoScenario(.backgroundEnforcement)
        #expect(model.isEnforcementRunning)
        #expect(!model.settings.autoShutdownEnabled)
        #expect(model.runtimeStateStore.recordURL == nil)
        #expect(model.isDemoSession)
        #expect(model.lockoutDeadlineStore.recordURL.path
            .hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    @Test("Background acceptance cannot terminate apps or shut down even after settings edits")
    func backgroundFixtureCannotShutDown() {
        let model = CurfewAppModel.demoModel(backgroundEnforcement: true)
        let controller = ShutdownControllerSpy(results: [true])
        model.shutdownController = controller
        model.settings.autoShutdownEnabled = true
        model.applyDemoScenario(.lockout)
        model.updateShutdownWorkflow(availability: true)
        model.currentTime = model.currentTime.addingTimeInterval(8 * 60 * 60)
        model.updateShutdownWorkflow(availability: true)
        #expect(controller.callLog.isEmpty)
        #expect(model.shutdownWorkflow.phase == .idle)
    }

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

    @Test("Browser demo state is connected, task scoped, and safe")
    func browserDemoState() {
        let settings = DemoFixture.browserIntegrationSettings()
        let work = DemoFixture.browserActiveWork(at: midday(2026, 4, 16))

        #expect(settings.setupIsComplete)
        #expect(settings.enforcementEnabled)
        #expect(settings.mappings.count == 1)
        #expect(settings.mappings[0].selector == .task("lvbt-social-strategy"))
        #expect(settings.mappings[0].scope.origin == "https://instagram.com")
        #expect(work.tracking == .paused)
        #expect(work.task?.title == "Complete LVBT social strategy")
    }

    @Test("Demo model cannot arm enforcement even through a visible start action")
    func demoModelCannotArmEnforcement() {
        let model = CurfewAppModel.demoModel()
        model.start()
        #expect(!model.isEnforcementRunning)
    }

    @Test("Schedule edits in demo mode cannot run enforcement even with shutdown enabled")
    func demoScheduleEditsCannotEnterEnforcementCycle() {
        let model = CurfewAppModel.demoModel()
        model.applyDemoScenario(.overview)
        let pinnedTime = model.currentTime
        let pinnedState = model.state
        model.settings.autoShutdownEnabled = true
        model.queueScheduleUpdate(model.settings.schedule)
        #expect(model.currentTime == pinnedTime)
        #expect(model.state == pinnedState)
        #expect(!model.isEnforcementRunning)
    }

    @Test("The menu bar never promises a lock while Curfew is off")
    func menuBarOffCopyIsHonest() {
        let model = CurfewAppModel.demoModel()
        model.applyDemoScenario(.overview)
        #expect(model.menuBarHeaderLine.contains("Curfew is off"))
        #expect(!model.menuBarHeaderLine.contains("until your Mac locks"))
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
