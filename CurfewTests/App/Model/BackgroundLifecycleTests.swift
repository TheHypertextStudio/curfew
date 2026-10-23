import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct BackgroundLifecycleTests {
    @Test("Enforcement reaches lockout with no ordinary windows")
    func closedWindowsReachLockout() async throws {
        var now = date(hour: 17, minute: 0)
        let model = makeModel(now: now, clock: { now })
        let windowsBefore = NSApplication.shared.windows.count
        model.start()
        #expect(model.state.phase == .working)
        now = date(hour: 19, minute: 0)
        try await Task.sleep(for: .seconds(1.3))
        #expect(model.state.phase == .locked)
        #expect(model.isEnforcementRunning)
        #expect(NSApplication.shared.windows.count == windowsBefore)
    }

    @Test("Uninstall stops the enforcement loop and wake cannot rearm it")
    func uninstallStopsEnforcement() {
        var now = date(hour: 19, minute: 0)
        let model = makeModel(now: now, clock: { now })
        model.start()
        #expect(model.state.phase == .locked)
        model.stopEnforcementForUninstall()
        #expect(!model.isEnforcementRunning)
        #expect(model.reassertEnforcementIfNeeded() == .noop)
        now = date(hour: 20, minute: 0)
        model.handleSystemWake()
        #expect(model.state.phase == .working)
    }

    @Test("Wake evaluates a missed deadline before reassertion")
    func wakeEvaluatesImmediately() {
        var now = date(hour: 17, minute: 0)
        let model = makeModel(now: now, clock: { now })
        model.start()
        now = date(hour: 19, minute: 0)
        model.handleSystemWake()
        #expect(model.currentTime == now)
        #expect(model.state.phase == .locked)
    }

    @Test("Deliberate reopen opens the main scene even when another window is visible")
    func reopenWithOverlayOrSettings() {
        let delegate = AppDelegate()
        var opened = false
        delegate.openMainWindow = { opened = true }
        #expect(!delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: true
        ))
        #expect(opened)
    }

    @Test("A background reopen never creates an ordinary window while the app stays inactive")
    func inactiveBackgroundReopenDoesNotOpenWindow() async {
        let delegate = AppDelegate()
        delegate.backgroundLaunch = true
        delegate.activationProbe = { false }
        var opened = false
        delegate.openMainWindow = { opened = true }
        #expect(!delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        ))
        await Task.yield()
        #expect(!opened)
        #expect(!delegate.applicationShouldOpenUntitledFile(NSApplication.shared))
    }

    private func makeModel(now: Date, clock: @escaping () -> Date) -> CurfewAppModel {
        let defaults = UserDefaults(suiteName: "CurfewBackgroundTests.\(UUID().uuidString)")!
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.hasCompletedInitialSetup = true
        settings.autoShutdownEnabled = false
        for day in Weekday.allCases {
            settings.schedule.rules[day] = DayRule(
                isDayOff: false,
                lockMinutes: 18 * 60,
                unlockMinutes: 7 * 60
            )
        }
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        return CurfewAppModel(
            settingsStore: store, appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            runtimeNow: now, enforcementClock: clock
        )
    }

    private func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }
}
