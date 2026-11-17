// Behavior tests for onboarding, settings UI, override composer.
//
// The original `FeatureBehaviorTests.swift` exceeded SwiftLint's file-length
// budget; the onboarding + UI-presentation surface lives here so each file
// stays under threshold and a reader looking for first-run flow tests can
// find them without paging through override-budget tests first.

import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct LocalAISetupCopyTests {
    @Test("Local AI setup describes its real authority without implying remote unlock")
    func localAISetupCopyIsTruthfulAndPlain() {
        #expect(SettingsView.integrationSectionOrder == [
            .localAI,
            .requestHandling,
            .taskBrowser,
            .helper
        ])

        let title = SettingsView.localAISectionTitle.lowercased()
        let explanation = SettingsView.localAIAuthorityDetails.lowercased()
        let setup = SettingsView.localAISetupExplanation.lowercased()

        #expect(title.contains("on this mac"))
        #expect(explanation.contains("can't grant an override"))
        #expect(explanation.contains("end the lock"))
        #expect(!explanation.contains("lock and unlock"))
        #expect(explanation.contains("declare work in progress"))
        #expect(explanation.contains("postpone shutdown"))
        #expect(explanation.contains("without asking"))
        #expect(setup.contains("add to claude desktop"))
        #expect(!setup.contains("stdio"))
        #expect(!setup.contains("mcpservers"))
    }
}

@MainActor
struct SetupUXTests {
    @Test("Open settings action activates app and opens Settings window route")
    func openSettingsActionRoutesThroughRouter() {
        let router = AppRouterSpy()
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
            ),
            appRouter: router,
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        model.openSettings()

        #expect(router.activateCallCount == 1)
        #expect(router.showSettingsCallCount == 1)
    }

    @Test("Getting Started action routes through the available scene")
    func gettingStartedActionRoutesThroughScene() {
        let router = AppRouterSpy()
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
            ),
            appRouter: router,
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        model.showGettingStarted()

        #expect(router.openedWindows == [CurfewAppModel.gettingStartedWindowID])
    }

    @Test("Completing onboarding marks setup complete and dismisses onboarding")
    func completeOnboardingFlowUpdatesState() {
        let router = AppRouterSpy()
        let suiteName = "CurfewSettingsStoreTests.OnboardingComplete.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: router,
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )

        #expect(!model.settings.hasCompletedInitialSetup)
        model.completeOnboardingFlow(choice: .remoteControlsOnly)
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(router.dismissedWindows == [CurfewAppModel.gettingStartedWindowID])
    }

    @Test("Completing setup without Accessibility trust does not arm enforcement")
    func completeInitialSetupRequiresAccessibilityTrust() {
        let suiteName = "CurfewSettingsStoreTests.OnboardingBypass.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        // Every UI surface that can call `completeInitialSetup()` — Today's
        // "Finish Setup" CTA and Settings' "Complete Setup" button — must be
        // unable to arm enforcement without a real Accessibility grant, or
        // the keyboard shield silently does nothing while the app believes
        // setup is done.
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: false)
        )

        model.completeInitialSetup(choice: .weeklySchedule)

        #expect(!model.settings.hasCompletedInitialSetup)
        #expect(!model.isEnforcementRunning)
    }
}

@MainActor
struct OverrideComposerStateTests {
    @Test("Override composer does not auto-open outside lockout")
    func composerStaysHiddenWhenNotLocked() {
        let model = makeTestAppModel()
        let now = Date()

        model.currentTime = now
        model.overridesRemaining = 1
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 20,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        model.reconcileOverrideComposerState(previousPhase: .working)
        #expect(!model.isOverrideComposerVisible)
    }

    @Test("Override composer state resets after leaving lockout")
    func composerStateResetsWhenLockoutEnds() {
        let model = makeTestAppModel()
        let now = Date()

        model.currentTime = now
        model.overridesRemaining = 1
        model.overrideReasonDraft = String(repeating: "x", count: 60)
        model.isOverrideComposerVisible = true
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 20,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        model.reconcileOverrideComposerState(previousPhase: .locked)

        #expect(!model.isOverrideComposerVisible)
        #expect(model.overrideReasonDraft.isEmpty)
    }
}
