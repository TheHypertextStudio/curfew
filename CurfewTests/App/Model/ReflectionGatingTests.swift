@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Wiring tests for the reflection-gate decision logic on `CurfewAppModel`:
/// which transitions raise the morning (daybreak) and evening gates, the
/// once-per-day suppression, the enable toggles, and the save/skip resolution.
@MainActor
struct ReflectionGatingTests {
    private func makeModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.reflection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
    }

    private func evaluation(phase: EnforcementPhase) -> CurfewEvaluation {
        CurfewEvaluation(
            phase: phase,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
    }

    @Test("Crossing into working raises the morning daybreak gate")
    func morningGateOnSession() {
        let model = makeModel()
        model.state = evaluation(phase: .working)

        model.evaluateReflectionGates(previousPhase: .dayOff)

        #expect(model.reflectionState.isDaybreakPresented)
        #expect(model.reflectionState.isEveningReflectionPending == false)
    }

    @Test("Crossing into locked raises the evening gate")
    func eveningGateOnLockout() {
        let model = makeModel()
        model.state = evaluation(phase: .locked)

        model.evaluateReflectionGates(previousPhase: .warning)

        #expect(model.reflectionState.isEveningReflectionPending)
        #expect(model.reflectionState.isDaybreakPresented == false)
    }

    @Test("A disabled gate never raises")
    func disabledGateStaysDown() {
        let model = makeModel()
        var config = ReflectionConfiguration.default
        config.morningEnabled = false
        model.updateReflectionConfiguration(config)
        model.state = evaluation(phase: .working)

        model.evaluateReflectionGates(previousPhase: .dayOff)

        #expect(model.reflectionState.isDaybreakPresented == false)
    }

    @Test("A gate resolved today does not re-prompt")
    func resolvedGateSuppressed() {
        let model = makeModel()
        model.reflectionState.gatesResolvedToday.insert(.evening)
        model.state = evaluation(phase: .locked)

        model.evaluateReflectionGates(previousPhase: .working)

        #expect(model.reflectionState.isEveningReflectionPending == false)
    }

    @Test("Leaving the working window dismisses a lingering daybreak overlay")
    func daybreakDismissedOffWorking() {
        let model = makeModel()
        model.reflectionState.isDaybreakPresented = true
        model.state = evaluation(phase: .warning)

        model.evaluateReflectionGates(previousPhase: .working)

        #expect(model.reflectionState.isDaybreakPresented == false)
    }

    @Test("An auto-dismissed daybreak overlay cannot resurrect later the same day")
    func daybreakDismissMarksResolvedToPreventResurrection() {
        let model = makeModel()
        // Simulate the overlay lingering unanswered into the lockout window —
        // the same sequence `daybreakDismissedOffWorking` exercises.
        model.reflectionState.isDaybreakPresented = true
        model.state = evaluation(phase: .locked)
        model.evaluateReflectionGates(previousPhase: .working)
        #expect(model.reflectionState.isDaybreakPresented == false)

        // An override grant (or any path) flips the phase back to `.working`
        // mid-lockout. Without marking `.morning` resolved on the earlier
        // auto-dismiss, this would be read as a fresh `→ working` transition
        // and re-raise the full-screen overlay hours after it was dismissed.
        model.state = evaluation(phase: .working)
        model.evaluateReflectionGates(previousPhase: .locked)

        #expect(model.reflectionState.isDaybreakPresented == false)
    }

    @Test("Saving a reflection resolves the gate and clears its surface")
    func saveResolvesGate() {
        let model = makeModel()
        model.reflectionState.isEveningReflectionPending = true

        model.saveReflection(
            gate: .evening,
            answers: [
                ReflectionAnswer(
                    promptID: UUID(),
                    promptTextSnapshot: "How did today go?",
                    value: .rating(value: 4, scale: 5)
                )
            ]
        )

        #expect(model.reflectionState.isEveningReflectionPending == false)
        #expect(model.reflectionState.gatesResolvedToday.contains(.evening))
        // A second lockout transition must not re-raise it the same day.
        model.state = evaluation(phase: .locked)
        model.evaluateReflectionGates(previousPhase: .working)
        #expect(model.reflectionState.isEveningReflectionPending == false)
    }

    @Test("Skipping resolves the gate without recording")
    func skipResolvesGate() {
        let model = makeModel()
        model.reflectionState.isDaybreakPresented = true

        model.skipReflection(gate: .morning)

        #expect(model.reflectionState.isDaybreakPresented == false)
        #expect(model.reflectionState.gatesResolvedToday.contains(.morning))
    }
}
