import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

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
        #expect(model.statusLine == "Work hours are active")

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "exclamationmark.triangle")
        #expect(model.statusLine == "Lockout approaching")

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
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}
