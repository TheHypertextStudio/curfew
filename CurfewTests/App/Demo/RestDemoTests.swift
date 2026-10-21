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
