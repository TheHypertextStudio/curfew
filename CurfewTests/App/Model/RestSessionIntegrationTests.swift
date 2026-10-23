@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct RestSessionIntegrationTests {
    private func model() -> CurfewAppModel {
        CurfewAppModel.demoModel()
    }

    private func locked(_ start: Date, _ end: Date) -> CurfewEvaluation {
        CurfewEvaluation(
            phase: .locked,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: start,
            unlockDate: end
        )
    }

    @Test("A delayed account hold cannot replace the scheduled morning anchor")
    func delayedReleaseRetainsScheduledMorning() throws {
        let model = model()
        model.applyDemoReviewState(.restContinuity)
        let scheduled = try #require(model.reflectionState.scheduledInterval)
        model.currentTime = scheduled.end.addingTimeInterval(60)
        model.state = locked(scheduled.start, .distantFuture)
        model.evaluateReflectionGates(previousPhase: .locked)
        #expect(model.reflectionState.scheduledInterval == scheduled)
        #expect(model.restPresentation.isMorning)
        #expect(model.restPresentation.isRestricted)
        #expect(model.restRestrictionStatus == .stillLocked)
    }

    @Test("Resolving yesterday's draft does not resolve tonight's occurrence")
    func saveAfterMidnightResolvesOriginalSession() throws {
        let model = model()
        model.applyDemoReviewState(.restContinuity)
        let interval = try #require(model.reflectionState.scheduledInterval)
        model.currentTime = interval.end.addingTimeInterval(-3600)
        model.resetReflectionGatesForNewDay()
        model.saveReflection(gate: .evening, answers: [])
        #expect(!model.reflectionState.gatesResolvedToday.contains(.evening))
        let tonight = interval.start.addingTimeInterval(24 * 3600)
        model.currentTime = tonight
        model.state = locked(tonight, interval.end.addingTimeInterval(24 * 3600))
        model.evaluateReflectionGates(previousPhase: .working)
        #expect(model.reflectionState.isEveningReflectionPending)
    }

    @Test("An unfinished evening survives natural unlock into a day off")
    func unfinishedEveningSurvivesDayOff() throws {
        let model = model()
        model.applyDemoReviewState(.restContinuity)
        let interval = try #require(model.reflectionState.scheduledInterval)
        let prompt = try #require(model.reflectionState.eveningDraft.prompts.first)
        model.reflectionState.eveningDraft.values[prompt.id] = .text("Keep this thought")
        model.currentTime = interval.end
        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.evaluateReflectionGates(previousPhase: .locked)
        #expect(model.shouldPresentRestScreen)
        #expect(model.restPresentation.layout == .evening)
        #expect(model.reflectionState.eveningDraft.values[prompt.id] == .text("Keep this thought"))
    }

    @Test("A remote temporary release does not begin morning or retain a blocking editor")
    func remoteOverrideDoesNotCreateMorning() throws {
        let model = model()
        model.applyDemoReviewState(.restContinuity)
        let deviceID = UUID()
        model.settings.accountSync = try AccountSyncConfiguration(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID, keyEpoch: 1, enrolledAt: model.currentTime
            ),
            releasePolicy: nil
        )
        model.accountRemoteOverride = AccountRemoteOverride(
            overrideID: UUID(), requestID: UUID(), targetDeviceIDs: [deviceID],
            reason: "Temporary access", durationMinutes: 5, startsAt: model.currentTime,
            authorizedBy: .mcpPreauthorizedClient, status: .active
        )
        let prompt = try #require(model.reflectionState.eveningDraft.prompts.first)
        model.reflectionState.eveningDraft.values[prompt.id] = .text("Continue later")
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 5,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.evaluateReflectionGates(previousPhase: .locked)
        #expect(!model.reflectionState.isDaybreakPresented)
        #expect(!model.shouldPresentRestScreen)
    }
}
