@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Wiring tests proving that the pure ``EnforcementHealth`` policy and the
/// ``AccessibilityAuthorizing`` seam are threaded into `CurfewAppModel` and
/// reflected in the menu-bar glyph.
///
/// The policy and the trust seam are unit-tested in isolation elsewhere
/// (`EnforcementHealthTests`, `AccessibilityAuthorizationTests`). These tests
/// instead assert the *integration*: that an untrusted machine drives the model
/// to ``EnforcementHealth/degradedNoAccessibility`` and swaps the menu-bar
/// symbol for the warning badge, while a trusted, unlocked machine stays
/// ``EnforcementHealth/active`` and shows the ordinary phase glyph.
@MainActor
struct EnforcementHealthWiringTests {
    @Test("Untrusted Accessibility degrades health and badges the menu bar")
    func untrustedDegradesAndBadgesMenuBar() {
        let model = makeModel(accessibilityTrusted: false)

        // Seeded from the fake before super.init, so the model knows it is
        // untrusted without a tick.
        #expect(model.isAccessibilityTrusted == false)

        // A working phase would normally show the clock glyph; degraded
        // enforcement must override it with the warning badge instead.
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 90,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.tick()

        #expect(model.enforcementHealth == .degradedNoAccessibility)
        #expect(model.menuBarSymbolName == "exclamationmark.triangle.fill")
    }

    @Test("Trusted and unlocked stays active and shows the phase glyph")
    func trustedAndUnlockedShowsPhaseGlyph() {
        let model = makeModel(accessibilityTrusted: true)

        #expect(model.isAccessibilityTrusted)

        // Poll directly rather than via `tick()`: the tick re-runs the
        // enforcement engine, which would overwrite this hand-set `.working`
        // phase from the (unconfigured) default schedule — making the asserted
        // glyph depend on the wall-clock time the suite happens to run. The
        // sibling tests below use the same seam for the same reason.
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 90,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.pollAndUpdateEnforcementHealth()

        #expect(model.enforcementHealth == .active)
        #expect(model.menuBarSymbolName == "clock.badge.checkmark")
    }

    @Test("Warning phase keeps a downed tap healthy and shows the warning glyph")
    func warningPhaseTapDownStaysActive() {
        let model = makeModel(accessibilityTrusted: true)
        // The keyboard shield is intentionally stopped during warning — the user
        // keeps full keyboard control while being warned — so a downed tap here
        // must NOT degrade health. Force "tap not firing" via the liveness seam.
        model.tapLivenessOverride = { false }

        // Poll directly rather than via `tick()`: the tick re-runs the
        // enforcement engine, which would overwrite this hand-set phase from the
        // (unconfigured) schedule before the health poll reads it.
        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fiveMinutes,
            minutesRemaining: 5,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.pollAndUpdateEnforcementHealth()

        #expect(model.enforcementHealth == .active)
        // The ordinary warning-phase glyph, NOT the degraded badge.
        #expect(model.menuBarSymbolName == "exclamationmark.triangle")
    }

    @Test("Trusted but a downed expected tap degrades health and badges the menu bar")
    func trustedTapDownDegradesAndBadgesMenuBar() {
        let model = makeModel(accessibilityTrusted: true)
        // The real CGEvent tap cannot run headlessly, so force "tap not firing"
        // through the liveness seam. Lockout marks the tap as expected-active.
        model.tapLivenessOverride = { false }

        // Poll directly rather than via `tick()`: the tick re-runs the
        // enforcement engine, which would overwrite this hand-set phase from the
        // (unconfigured) schedule before the health poll reads it.
        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.pollAndUpdateEnforcementHealth()

        #expect(model.enforcementHealth == .degradedTapDown)
        #expect(model.menuBarSymbolName == "exclamationmark.triangle.fill")
    }

    @Test("Requesting access prompts for trust and recomputes health immediately")
    func requestAccessibilityRecomputesHealthWithoutTick() {
        let fake = FakeAccessibilityAuthorization(trusted: true)
        let model = makeModel(authorization: fake)
        // Establish a tap-down verdict first so the recompute has something
        // other than the trust flip to move. Poll directly (not via `tick()`)
        // so the engine does not overwrite this hand-set lockout phase.
        model.tapLivenessOverride = { false }
        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.pollAndUpdateEnforcementHealth()
        #expect(model.enforcementHealth == .degradedTapDown)

        // Revoke trust, then request access. Without a tick, health must still
        // move to the no-accessibility verdict because the request recomputes it.
        fake.trusted = false
        let promptsBefore = fake.promptForTrustCallCount
        model.requestAccessibilityAccess()

        #expect(fake.promptForTrustCallCount == promptsBefore + 1)
        #expect(model.isAccessibilityTrusted == false)
        #expect(model.enforcementHealth == .degradedNoAccessibility)
    }

    @Test("Refreshing trust re-polls the seam without prompting or a tick")
    func refreshAccessibilityTrustRepollsWithoutPrompting() {
        // Onboarding's permissions gate refreshes trust before enforcement is
        // ever started, so the refresh path must be a pure read of the seam —
        // never the prompting API — and must move `isAccessibilityTrusted`
        // without a `tick()`.
        let fake = FakeAccessibilityAuthorization(trusted: false)
        let model = makeModel(authorization: fake)
        #expect(model.isAccessibilityTrusted == false)

        fake.trusted = true
        model.refreshAccessibilityTrust()
        #expect(model.isAccessibilityTrusted)
        #expect(fake.promptForTrustCallCount == 0)

        fake.trusted = false
        model.refreshAccessibilityTrust()
        #expect(model.isAccessibilityTrusted == false)
        #expect(fake.promptForTrustCallCount == 0)
    }

    // MARK: - Helpers

    /// Builds a `CurfewAppModel` wired to a ``FakeAccessibilityAuthorization``
    /// with the given trust value, mirroring the isolated-defaults pattern in
    /// `LifecycleWiringTests.makeModel`.
    private func makeModel(accessibilityTrusted: Bool) -> CurfewAppModel {
        makeModel(
            authorization: FakeAccessibilityAuthorization(trusted: accessibilityTrusted)
        )
    }

    /// Builds a `CurfewAppModel` wired to the supplied trust fake, so a test
    /// can keep a reference to assert prompt-call counts after construction.
    private func makeModel(
        authorization: FakeAccessibilityAuthorization
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            accessibilityAuthorization: authorization
        )
    }
}
