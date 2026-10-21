@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct RestDemoTests {
    @Test("The rest continuity fixture has an editable reflection and never arms enforcement")
    func continuityIsEditableAndDisarmed() {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restContinuity)
        #expect(model.reflectionState.isEveningReflectionPending)
        #expect(model.reflectionState.eveningDraft.prompts.contains { $0.kind == .text })
        #expect(!model.isEnforcementRunning)
        #expect(!model.settings.autoShutdownEnabled)
    }

    @Test("A rest demo never reasserts the real enforcement shield")
    func restDemoDoesNotReassertEnforcement() {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restContinuity)
        #expect(model.reassertEnforcementIfNeeded() == .noop)
        #expect(!model.isEnforcementRunning)
    }

    @Test("Physical demo resume advances the current scene without discarding its draft")
    func demoResumeUsesElapsedWallTime() throws {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restContinuity)
        let clock = try #require(model.reflectionState.demoRestClock)
        let draft = model.reflectionState.eveningDraft
        let prompt = try #require(draft.prompts.first)
        draft.values[prompt.id] = .text("Keep this through sleep")
        model.refreshDemoRestClock(at: clock.wallStart.addingTimeInterval(3600))
        #expect(model.currentTime == clock.sceneStart.addingTimeInterval(3600))
        #expect(model.reflectionState.eveningDraft === draft)
        #expect(model.reflectionState.isEveningReflectionPending)
        #expect(draft.values[prompt.id] == .text("Keep this through sleep"))
        #expect(!model.isEnforcementRunning)
    }

    @Test("The hold fixture advances the clock without arming enforcement")
    func holdFixtureIsDisarmedAndReady() {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restHold)
        #expect(model.reflectionState.demoRestClock != nil)
        #expect(model.isOverrideComposerVisible)
        #expect(model.overrideCooldownRemaining == 0)
        #expect(!model.overrideReasonDraft.isEmpty)
        #expect(!model.isEnforcementRunning)
    }

    @Test("The morning fixture follows its retained scheduled interval")
    func morningIsScheduledAndDisarmed() throws {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restMorning)
        let interval = try #require(model.reflectionState.scheduledInterval)
        #expect(model.currentTime >= interval.end)
        #expect(model.reflectionState.isDaybreakPresented)
        #expect(!model.isEnforcementRunning)
    }
}
