// Behavior tests for onboarding, settings UI, override composer, and
// menu bar presentation.
//
// The original `FeatureBehaviorTests.swift` exceeded SwiftLint's file-length
// budget; the onboarding + UI-presentation surface lives here so each file
// stays under threshold and a reader looking for first-run flow tests can
// find them without paging through override-budget tests first.

import AppKit
@testable import Curfew
import CurfewKit
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
        #expect(message.contains("thinking clearly"))
        #expect(message.contains("enforce"))
    }

    @Test("Schedule step copy explains when work ends and resumes")
    func scheduleCopyUsesWorkWindowLanguage() {
        let message = FirstRunStep.schedule.message.lowercased()
        #expect(message.contains("work ends"))
        #expect(message.contains("work resumes"))
    }
}

@MainActor
struct SetupUXTests {
    @Test("Open settings action activates app and opens Settings window route")
    func openSettingsActionRoutesThroughRouter() {
        let router = AppRouterSpy()
        let model = CurfewAppModel(
            appRouter: router,
            gettingStartedPresenter: GettingStartedPresenterSpy()
        )

        model.openSettings()

        #expect(router.activateCallCount == 1)
        #expect(router.showSettingsCallCount == 1)
    }

    @Test("Getting Started action presents onboarding window route")
    func gettingStartedActionRoutesThroughPresenter() {
        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        model.showGettingStarted()

        #expect(presenter.presentCallCount == 1)
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

        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        #expect(!model.settings.hasCompletedInitialSetup)
        model.completeOnboardingFlow()
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(presenter.dismissCallCount == 1)
    }
}

@MainActor
struct OverrideComposerStateTests {
    @Test("Override composer does not auto-open outside lockout")
    func composerStaysHiddenWhenNotLocked() {
        let model = CurfewAppModel()
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
        let model = CurfewAppModel()
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
        let model = CurfewAppModel()

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
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            activityRecorder: NullActivityRecording(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}
