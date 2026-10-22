@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct RestAppearanceSceneTests {
    @Test("Missing scheduled data cannot borrow a remote restriction's Sunrise")
    func missingScheduleStaysNeutral() {
        let model = CurfewAppModel.demoModel()
        model.reflectionState.scheduledInterval = nil
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .none, minutesRemaining: 5,
            canRequestExtension: false,
            lockDate: model.currentTime.addingTimeInterval(-3600),
            unlockDate: model.currentTime.addingTimeInterval(300)
        )
        let scene = RestScreenView(model: model, display: RestDisplayPresentation()).sceneSnapshot
        #expect(scene.lockDate == nil)
        #expect(scene.unlockDate == nil)
        #expect(scene.resolve(at: model.currentTime, timeZone: .current).phase == .allDay)
        #expect(model.state.phase == .locked)
    }

    @Test("The actual rest renderer keeps the scheduled morning under stronger restrictions")
    func retainedScheduleAnchorsMorning() throws {
        let model = CurfewAppModel.demoModel()
        model.applyDemoReviewState(.restContinuity)
        let interval = try #require(model.reflectionState.scheduledInterval)
        model.currentTime = interval.end.addingTimeInterval(60)
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .none, minutesRemaining: 60,
            canRequestExtension: false,
            lockDate: interval.start, unlockDate: interval.end.addingTimeInterval(3600)
        )
        let scene = RestScreenView(model: model, display: RestDisplayPresentation()).sceneSnapshot
        #expect(scene.lockDate == interval.start)
        #expect(scene.unlockDate == interval.end)
        #expect(scene.resolve(at: model.currentTime, timeZone: .current).phase == .morning)
        #expect(model.isEnforcingLockout)
    }
}
