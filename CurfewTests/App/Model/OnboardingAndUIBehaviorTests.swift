// Behavior tests for onboarding, settings UI, override composer, and
// menu bar presentation.
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

struct FirstRunFlowTests {
    @Test("First-run flow contains required setup steps")
    func requiredSteps() {
        #expect(
            FirstRunStep.allCases == [
                .welcome,
                .schedule,
                .extensionBudget,
                .permissions,
                .confirmation
            ]
        )
    }

    @Test("First-run flow advances and retreats within bounds")
    func navigationBounds() {
        var flow = FirstRunFlow()
        #expect(flow.currentStep == .welcome)

        flow.retreat()
        #expect(flow.currentStep == .welcome)

        flow.advance()
        #expect(flow.currentStep == .schedule)
        flow.advance()
        #expect(flow.currentStep == .schedule)

        flow.markScheduleReviewed()
        #expect(flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .extensionBudget)
        flow.advance()
        #expect(flow.currentStep == .permissions)
        flow.advance()
        #expect(flow.currentStep == .permissions)

        flow.updateAccessibilityGranted(true)
        #expect(flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .confirmation)

        flow.advance()
        #expect(flow.currentStep == .confirmation)
    }

    @Test("Schedule step blocks progress until settings review is recorded")
    func scheduleStepRequiresReview() {
        var flow = FirstRunFlow()

        flow.advance()
        #expect(flow.currentStep == .schedule)
        #expect(!flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .schedule)

        flow.markScheduleReviewed()
        #expect(flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .extensionBudget)
    }

    @Test("Opening the schedule editor alone cannot authorize automatic lockout")
    func openingScheduleDoesNotConfirmIt() {
        var flow = FirstRunFlow()
        flow.advance()

        flow.markScheduleReviewed()

        #expect(!flow.canAdvance)
        flow.advance()
        #expect(flow.currentStep == .schedule)
    }

    @Test("Permissions step blocks finish path until accessibility is actually granted")
    func permissionsStepRequiresAccessibilityGrant() {
        var flow = FirstRunFlow()

        flow.advance()
        flow.markScheduleReviewed()
        flow.advance()
        flow.advance()

        #expect(flow.currentStep == .permissions)
        #expect(!flow.canAdvance)

        // Self-attestation is gone: advancing without a real grant is a no-op.
        flow.advance()
        #expect(flow.currentStep == .permissions)

        flow.updateAccessibilityGranted(true)
        #expect(flow.canAdvance)

        flow.advance()
        #expect(flow.currentStep == .confirmation)
        #expect(flow.canFinish)
    }

    @Test("Permissions step re-locks when accessibility trust is revoked")
    func permissionsStepRelocksWhenTrustRevoked() {
        var flow = FirstRunFlow()

        flow.advance()
        flow.markScheduleReviewed()
        flow.advance()
        flow.advance()
        #expect(flow.currentStep == .permissions)

        flow.updateAccessibilityGranted(true)
        #expect(flow.canAdvance)

        // A live re-poll that now reports false must re-close the gate so the
        // user cannot advance on a stale "granted" reading.
        flow.updateAccessibilityGranted(false)
        #expect(!flow.canAdvance)
        #expect(!flow.isAccessibilityGranted)
    }
}

struct GettingStartedCopyTests {
    @Test("Getting started copy reinforces commitment and enforcement model")
    func warmCommitmentCopy() {
        let message = GettingStartedCopy.commitmentMessage.lowercased()
        #expect(message.contains("stop"))
        #expect(message.contains("stick"))
    }

    @Test("Schedule step copy explains when work ends and resumes")
    func scheduleCopyUsesWorkWindowLanguage() {
        let message = FirstRunStep.schedule.message.lowercased()
        #expect(message.contains("locks"))
        #expect(message.contains("unlocks"))
    }

    @Test("Local AI setup describes its real authority without implying remote unlock")
    func localAISetupCopyIsTruthfulAndPlain() {
        #expect(SettingsView.integrationSectionOrder.prefix(2) == [.account, .localAI])

        let title = SettingsView.localAISectionTitle.lowercased()
        let explanation = SettingsView.localAIExplanation.lowercased()
        let setup = SettingsView.localAISetupExplanation.lowercased()

        #expect(title.contains("on this mac"))
        #expect(explanation.contains("cannot grant an override"))
        #expect(explanation.contains("cannot end an active lockout"))
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
    @Test("First-run schedule edits replace the draft immediately without cooldown")
    func firstRunScheduleEditIsImmediate() {
        let suiteName = "CurfewSettingsStoreTests.InitialSchedule.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes = 22 * 60

        model.queueScheduleUpdate(proposed)

        #expect(model.settings.schedule.rule(for: .monday).lockMinutes == 22 * 60)
        #expect(model.settings.pendingScheduleChange == nil)
    }

    @Test("Open settings action activates app and opens Settings window route")
    func openSettingsActionRoutesThroughRouter() {
        let router = AppRouterSpy()
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
            ),
            appRouter: router,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        model.openSettings()

        #expect(router.activateCallCount == 1)
        #expect(router.showSettingsCallCount == 1)
    }

    @Test("Getting Started action bumps the onboarding window request trigger")
    func gettingStartedActionBumpsRequestTrigger() {
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(
                defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
            ),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        model.showGettingStarted()

        #expect(model.gettingStartedRequestID == 1)
    }

    @Test("Completing onboarding marks setup complete and dismisses onboarding")
    func completeOnboardingFlowUpdatesState() {
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
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )

        #expect(!model.settings.hasCompletedInitialSetup)
        model.completeOnboardingFlow()
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(model.gettingStartedDismissID == 1)
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
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: false)
        )

        model.completeInitialSetup()

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

@MainActor
struct MenuBarPresentationModelTests {
    @Test("Menu bar symbol and status line reflect enforcement phase")
    func symbolAndStatusForPhase() {
        // Build a model that holds Accessibility trust so `enforcementHealth`
        // seeds to `.active`; otherwise the warning badge would override the
        // per-phase glyph this test is asserting. Enforcement degradation has
        // its own coverage in `EnforcementHealthWiringTests`.
        let model = makeTrustedModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 90,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "clock.badge.checkmark")
        #expect(model.statusLine == "Working window active")

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "exclamationmark.triangle")
        #expect(model.statusLine == "Wrap up time")

        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "lock.fill")
        #expect(model.statusLine == "Curfew lockout active")

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "moon.zzz")
        #expect(model.statusLine == "Day off")
    }

    @Test("Menu bar countdown uses h:mm formatting and day-off placeholder")
    func timeRemainingTextFormatting() {
        let model = makeTestAppModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 125,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "2:05")

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "—")
    }

    /// Builds a `CurfewAppModel` over isolated defaults and a trusted
    /// ``FakeAccessibilityAuthorization`` so `enforcementHealth` seeds to
    /// `.active`, letting the per-phase menu-bar glyph show through.
    private func makeTrustedModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}
