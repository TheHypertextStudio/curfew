@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Wiring tests proving that `CurfewAppModel.reassertEnforcementIfNeeded()` —
/// the entry point the AppDelegate calls on app activation and the model calls
/// on system wake — re-polls enforcement health and re-asserts the lockout
/// shield only while locked.
///
/// The pure decision is unit-tested in `EnforcementReassertionPolicyTests`;
/// these assert the integration: the model folds the live trust seam back into
/// `enforcementHealth` and returns the policy verdict so a degraded lockout
/// recovers when the user returns.
@MainActor
struct EnforcementReassertionWiringTests {
    @Test("Activation while locked re-polls health and re-asserts enforcement")
    func lockedReassertsAndRepollsHealth() {
        let trust = FakeAccessibilityAuthorization(trusted: true)
        let model = makeModel(accessibilityAuthorization: trust)
        // The real CGEvent tap cannot run headlessly; force "tap down" so the
        // re-poll would compute the degraded verdict were trust still present.
        model.tapLivenessOverride = { false }
        model.state = lockedState

        // Flip trust away after seeding so the re-assert's re-poll has a change
        // to surface: if it polls, `isAccessibilityTrusted` moves to false.
        trust.trusted = false
        let decision = model.reassertEnforcementIfNeeded()

        #expect(decision == .reassert)
        #expect(model.isAccessibilityTrusted == false)
        #expect(model.enforcementHealth == .degradedNoAccessibility)
    }

    @Test("Activation while not locked is a no-op but still re-polls health")
    func unlockedIsNoopButRepolls() {
        let trust = FakeAccessibilityAuthorization(trusted: true)
        let model = makeModel(accessibilityAuthorization: trust)
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 90,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        trust.trusted = false
        let decision = model.reassertEnforcementIfNeeded()

        #expect(decision == .noop)
        // Health is still re-polled even when no re-assertion is needed, so a
        // revoked permission surfaces the moment the user returns.
        #expect(model.isAccessibilityTrusted == false)
        #expect(model.enforcementHealth == .degradedNoAccessibility)
    }

    @Test("Re-assert is safe to call repeatedly while locked")
    func reassertIsIdempotent() {
        let model = makeModel(
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        model.tapLivenessOverride = { false }
        model.state = lockedState

        #expect(model.reassertEnforcementIfNeeded() == .reassert)
        #expect(model.reassertEnforcementIfNeeded() == .reassert)
        #expect(model.enforcementHealth == .degradedTapDown)
    }

    // MARK: - Fixtures

    private var lockedState: CurfewEvaluation {
        CurfewEvaluation(
            phase: .locked,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
    }

    private func makeModel(
        accessibilityAuthorization: FakeAccessibilityAuthorization
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            accessibilityAuthorization: accessibilityAuthorization
        )
    }
}
