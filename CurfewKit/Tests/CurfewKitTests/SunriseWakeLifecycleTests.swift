@testable import CurfewKit
import Foundation
import Testing

extension SunriseWakeCoordinatorTests {
    @Test func dismissalReleasesOnlyThisOccurrenceWithoutReacquiringIt() async throws {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan(offset: 0)
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        try #require(effects.delivery.isActive)
        try subject.dismissCurrentOccurrence()
        #expect(!effects.delivery.isActive)
        #expect(effects.calls.filter { $0 == "release" }.count == 1)
        await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: now.addingTimeInterval(1)
        )
        #expect(!effects.delivery.isActive)
        #expect(effects.calls.filter { $0 == "acquire" }.count == 1)
        let next = plan(offset: 0)
        await subject.reconcile(plan: next, enabled: true, onExternalPower: true, now: now)
        #expect(effects.delivery.isActive)
        #expect(effects.calls.filter { $0 == "acquire" }.count == 2)
    }

    @Test func freshReturnTimeDismissesSunriseBeforeTheFirstResumeTick() async throws {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan()
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        try subject.dismissCurrentOccurrence(at: desired.wakeAt)
        await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: desired.wakeAt
        )
        #expect(!effects.delivery.isActive)
        #expect(!effects.calls.contains("activity"))
        #expect(!effects.calls.contains("acquire"))
        #expect(subject.status == .dismissed)
    }

    @Test func helperLifecycleChangeInvalidatesAcceptanceOfAnUnchangedPlan() async {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan()
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        #expect(subject.status == .scheduled)
        subject.invalidateHelperAcceptance()
        #expect(subject.status == .helperUnavailable)
        effects.failure = .unavailable
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        #expect(subject.status == .helperUnavailable)
        effects.failure = nil
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        #expect(subject.status == .scheduled)
        #expect(effects.calls.filter { $0 == "replace" }.count == 3)
    }
}
