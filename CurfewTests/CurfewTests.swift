import Testing
import Foundation
import CoreGraphics
@testable import Curfew

struct CurfewTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test("Initial setup prompt is shown only once")
    func initialSetupPromptShownOnlyOnce() {
        let suiteName = "CurfewSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)

        #expect(store.consumeShouldShowInitialSetup())
        #expect(!store.consumeShouldShowInitialSetup())
    }

    @Test("Default settings start with setup incomplete")
    func setupStartsIncompleteByDefault() {
        #expect(!CurfewSettings.default.hasCompletedInitialSetup)
    }

    @MainActor
    @Test("Enforcement does not start until setup is explicitly completed")
    func enforcementArmsOnlyAfterSetupCompletion() {
        let suiteName = "CurfewSettingsStoreTests.SetupArming.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: SetupArmingAppRouterSpy(),
            gettingStartedPresenter: SetupArmingPresenterSpy()
        )

        model.start()
        #expect(!model.isEnforcementRunning)
        #expect(!model.settings.hasCompletedInitialSetup)

        model.completeInitialSetup()
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(model.isEnforcementRunning)
    }

}

@MainActor
private final class SetupArmingAppRouterSpy: AppRouting {
    func activate() {}
    func showSettings() {}
}

@MainActor
private final class SetupArmingPresenterSpy: GettingStartedPresenting {
    func present(model: CurfewAppModel) {}
    func dismiss() {}
}

struct WarningBehaviorTests {
    @Test("Snooze action is only offered in thirty and fifteen-minute warning stages")
    func snoozeActionAvailability() {
        #expect(WarningStage.thirtyMinutes.supportsSnooze)
        #expect(WarningStage.fifteenMinutes.supportsSnooze)
        #expect(!WarningStage.fiveMinutes.supportsSnooze)
        #expect(!WarningStage.twoMinutes.supportsSnooze)
        #expect(!WarningStage.oneMinute.supportsSnooze)
        #expect(!WarningStage.lockout.supportsSnooze)
    }

    @Test("Floating countdown timer is shown only during final five minutes")
    func floatingTimerStageAvailability() {
        #expect(WarningStage.fiveMinutes.showsFloatingTimer)
        #expect(WarningStage.twoMinutes.showsFloatingTimer)
        #expect(WarningStage.oneMinute.showsFloatingTimer)
        #expect(!WarningStage.fifteenMinutes.showsFloatingTimer)
        #expect(!WarningStage.lockout.showsFloatingTimer)
    }
}

struct LockoutShortcutPolicyTests {
    @Test("Policy blocks targeted lockout shortcut combinations")
    func blocksTargetedShortcuts() {
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 48, flags: [.maskCommand])) // Cmd+Tab
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 12, flags: [.maskCommand])) // Cmd+Q
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 49, flags: [.maskCommand])) // Cmd+Space
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 53, flags: [.maskCommand, .maskAlternate])) // Cmd+Opt+Esc
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 123, flags: [.maskControl])) // Ctrl+Left
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 124, flags: [.maskControl])) // Ctrl+Right
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 125, flags: [.maskControl])) // Ctrl+Down
        #expect(LockoutShortcutPolicy.shouldBlock(keyCode: 126, flags: [.maskControl])) // Ctrl+Up
    }

    @Test("Policy allows unrelated keystrokes")
    func allowsUnrelatedShortcuts() {
        #expect(!LockoutShortcutPolicy.shouldBlock(keyCode: 0, flags: [.maskCommand])) // Cmd+A should pass
        #expect(!LockoutShortcutPolicy.shouldBlock(keyCode: 49, flags: [])) // Space by itself should pass
        #expect(!LockoutShortcutPolicy.shouldBlock(keyCode: 53, flags: [.maskCommand])) // Cmd+Esc should pass
    }
}

struct AccessibilityConfigurationTests {
    @Test("Reduce motion disables lockout background animation")
    func reduceMotionConfiguration() {
        let animated = LockoutVisualConfiguration.resolve(
            reduceMotion: false,
            reduceTransparency: false
        )
        let reduced = LockoutVisualConfiguration.resolve(
            reduceMotion: true,
            reduceTransparency: false
        )

        #expect(animated.animateBackground)
        #expect(!reduced.animateBackground)
    }

    @Test("Reduce transparency switches to stronger solid panel treatment")
    func reduceTransparencyConfiguration() {
        let reducedTransparency = LockoutVisualConfiguration.resolve(
            reduceMotion: false,
            reduceTransparency: true
        )

        #expect(reducedTransparency.usesSolidPanels)
    }

    @Test("VoiceOver copy includes message and unlock information")
    func voiceOverSummaryIncludesUnlockCopy() {
        let summary = LockoutAccessibilityCopy.summary(
            message: "Great work today.",
            unlockLine: "Your computer unlocks at 8:00 AM"
        )

        #expect(summary.contains("Great work today."))
        #expect(summary.contains("8:00 AM"))
    }
}

private final class ShutdownControllerSpy: ShutdownControlling {
    private(set) var callLog: [String] = []
    private var results: [Bool]

    init(results: [Bool]) {
        self.results = results
    }

    func requestGracefulTermination() {
        callLog.append("graceful")
    }

    func executeShutdown() -> Bool {
        callLog.append("shutdown")
        guard !results.isEmpty else {
            return false
        }
        return results.removeFirst()
    }
}

struct ShutdownWorkflowTests {
    @Test("Workflow requests graceful termination before issuing shutdown command")
    func gracefulBeforeShutdown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [true])

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 1),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        #expect(spy.callLog == ["graceful", "shutdown"])
        #expect(workflow.phase == .completed)
    }

    @Test("Workflow retries once after sixty seconds when first shutdown attempt fails")
    func retriesOnceAfterFailure() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [false, true])

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 1),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        #expect(workflow.phase == .retryScheduled(at: now.addingTimeInterval(10 * 60 + 1 + 60)))

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 62),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        #expect(workflow.phase == .completed)
    }

    @Test("Workflow remains failed and does not keep retrying after second failure")
    func failureAfterRetryKeepsLockoutState() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [false, false])

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 1),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 62),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        #expect(workflow.phase == .failed)

        workflow.update(
            now: now.addingTimeInterval(10 * 60 + 120),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        #expect(workflow.phase == .failed)
        #expect(spy.callLog == ["graceful", "shutdown", "graceful", "shutdown"])
    }

}
