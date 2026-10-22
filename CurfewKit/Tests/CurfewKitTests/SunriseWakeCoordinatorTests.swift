@testable import CurfewKit
import Foundation
import Testing

/// Contracts awaiting behavioral RED on the allocated test host.
@MainActor
struct SunriseWakeCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func plan(offset: TimeInterval = 600, battery: Bool = false) -> SunriseWakePlan {
        SunriseWakePlan(
            owner: "curfew.test", occurrenceID: UUID(),
            wakeAt: now.addingTimeInterval(offset),
            holdUntil: now.addingTimeInterval(offset + 900), allowsBattery: battery
        )
    }

    @Test func defaultsAreDisabled() async {
        let effects = Effects()
        let subject = effects.subject()
        await subject.reconcile(plan: plan(), onExternalPower: true, now: now)
        #expect(subject.status == .disabled)
        #expect(!effects.calls.contains("replace"))
        #expect(!effects.calls.contains("activity"))
        #expect(!effects.calls.contains("acquire"))
    }

    @Test func futurePlanIsScheduledOnceAcrossClockAndWakeNotifications() async {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan()
        for _ in 0 ..< 3 {
            await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        }
        #expect(effects.calls == ["replace"])
        #expect(effects.plans == [desired])
        #expect(effects.deadlines.isEmpty)
        #expect(subject.status == .scheduled)
    }

    @Test func wakeWindowCancelsFutureEventAndDeliversOnceAtExactDeadline() async {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan()
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        for _ in 0 ..< 3 {
            await subject.reconcile(
                plan: desired, enabled: true, onExternalPower: true, now: desired.wakeAt
            )
        }
        #expect(effects.calls == ["replace", "cancel", "activity", "acquire"])
        #expect(effects.deadlines == [desired.holdUntil])
        #expect(effects.delivery.isActive)
        #expect(subject.status == .displayRequested)
        await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: desired.holdUntil
        )
        #expect(!effects.delivery.isActive)
        #expect(effects.calls.contains("release"))
        #expect(effects.calls.contains("cleanup"))
    }

    @Test func unavailableHelperDoesNotBlockIndependentDisplayRequest() async {
        let effects = Effects()
        effects.cancelFailure = .unavailable
        let subject = effects.subject()
        let desired = plan(offset: 0)
        await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: now
        )
        #expect(effects.calls.contains("cancel"))
        #expect(effects.calls.contains("activity"))
        #expect(effects.deadlines == [desired.holdUntil])
        #expect(effects.delivery.isActive)
        #expect(subject.status == .helperUnavailable)
    }

    @Test func cancellationFailureIsRejectedAndRetriedOnlyOnExplicitReconcile() async {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan()
        await subject.reconcile(plan: desired, enabled: true, onExternalPower: true, now: now)
        effects.cancelFailure = .rejected
        await subject.reconcile(plan: nil, onExternalPower: true, now: now)
        #expect(subject.status == .requestRejected)
        #expect(!effects.calls.contains("activity"))
        let cancellationCount = effects.calls.filter { $0 == "cancel" }.count
        #expect(cancellationCount == 1)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(effects.calls.filter { $0 == "cancel" }.count == cancellationCount)
        effects.cancelFailure = nil
        await subject.reconcile(plan: nil, onExternalPower: true, now: now)
        #expect(effects.calls.filter { $0 == "cancel" }.count == cancellationCount + 1)
        #expect(subject.status == .disabled)
    }

    @Test func cleanupFailureIsRejectedAndRetriedWithoutNewActivity() async {
        let effects = Effects()
        let subject = effects.subject()
        let desired = plan(offset: 0)
        await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: now
        )
        effects.calls.removeAll()
        effects.failCleanup = true
        await subject.reconcile(plan: nil, onExternalPower: true, now: now)
        #expect(subject.status == .requestRejected)
        #expect(effects.calls.contains("cleanup"))
        #expect(!effects.calls.contains("activity"))
        #expect(!effects.calls.contains("acquire"))
        let cleanupCount = effects.calls.filter { $0 == "cleanup" }.count
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(effects.calls.filter { $0 == "cleanup" }.count == cleanupCount)
        effects.failCleanup = false
        await subject.reconcile(plan: nil, onExternalPower: true, now: now)
        #expect(effects.calls.filter { $0 == "cleanup" }.count == cleanupCount + 1)
        #expect(subject.status == .disabled)
        #expect(!effects.delivery.isActive)
    }

    @Test func missingScheduleAndBatteryExclusionHaveDistinctStates() async {
        let effects = Effects()
        let subject = effects.subject()
        await subject.reconcile(plan: nil, enabled: true, onExternalPower: true, now: now)
        #expect(subject.status == .waitingForSchedule)
        await subject.reconcile(plan: plan(), enabled: true, onExternalPower: false, now: now)
        #expect(subject.status == .batteryExcluded)
        #expect(!effects.calls.contains("replace"))
    }

    @Test func helperUnavailableAndRejectedAreDistinct() async {
        for failure in [SunriseWakeCoordinator.HelperFailure.unavailable, .rejected] {
            let effects = Effects()
            effects.failure = failure
            let subject = effects.subject()
            await subject.reconcile(plan: plan(), enabled: true, onExternalPower: true, now: now)
            #expect(subject
                .status == (failure == .unavailable ? .helperUnavailable : .requestRejected))
            #expect(!effects.delivery.isActive)
        }
    }

    @Test func scheduleReplacementAndBatteryOptOutCancelOwnership() async {
        let effects = Effects()
        let subject = effects.subject()
        let original = plan(battery: true)
        let changed = plan(offset: 1200, battery: true)
        await subject.reconcile(
            plan: original, enabled: true, batteryOptIn: true, onExternalPower: false, now: now
        )
        await subject.reconcile(
            plan: changed, enabled: true, batteryOptIn: true, onExternalPower: false, now: now
        )
        #expect(effects.plans == [original, changed])
        await subject.reconcile(
            plan: changed, enabled: true, batteryOptIn: false, onExternalPower: false, now: now
        )
        #expect(effects.calls.last == "cancel")
        #expect(effects.calls.contains("cleanup"))
        #expect(subject.status == .batteryExcluded)
    }
}

extension SunriseWakeCoordinatorTests {
    @Test func disableCleansDisplayImmediatelyAndSerializesCancelAfterInflightReplace() async {
        let effects = Effects()
        let desired = plan()
        // Seed an already-owned display assertion without real power operations.
        _ = try? effects.delivery.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: desired.wakeAt
        )
        effects.calls.removeAll()
        effects.suspendReplace = true
        let subject = effects.subject()
        let replacing = Task { await subject.reconcile(
            plan: desired, enabled: true, onExternalPower: true, now: now
        ) }
        let started = await effects.waitForSuspendedReplace()
        #expect(started, "Replace must start before disable is exercised")
        guard started else {
            effects.suspendReplace = false
            effects.finishReplace()
            await replacing.value
            return
        }
        let disabling = Task {
            effects.secondaryReconcileStarted = true
            await subject.reconcile(
                plan: nil, enabled: false, onExternalPower: true, now: now
            )
        }
        let disableStarted = await effects.waitForSecondaryReconcile()
        #expect(disableStarted, "Disable must enter reconcile before inspecting cleanup")
        #expect(!effects.delivery.isActive)
        #expect(effects.calls.contains("release"))
        #expect(effects.calls.contains("cleanup"))
        #expect(!effects.calls.contains("cancel"), "Cancel must wait for the older replace")
        effects.suspendReplace = false
        effects.finishReplace()
        await replacing.value
        await disabling.value
        #expect(effects.calls.last == "cancel")
        #expect(subject.status == .disabled)
    }

    @Test func newerPlanExecutesAfterInflightReplaceAndWinsStatus() async {
        let effects = Effects()
        effects.suspendReplace = true
        let subject = effects.subject()
        let original = plan()
        let changed = plan(offset: 1200)
        let first = Task { await subject.reconcile(
            plan: original, enabled: true, onExternalPower: true, now: now
        ) }
        let started = await effects.waitForSuspendedReplace()
        #expect(started)
        guard started else {
            effects.suspendReplace = false
            effects.finishReplace()
            await first.value
            return
        }
        let second = Task {
            effects.secondaryReconcileStarted = true
            await subject.reconcile(
                plan: changed, enabled: true, onExternalPower: true, now: now
            )
        }
        let secondStarted = await effects.waitForSecondaryReconcile()
        #expect(secondStarted, "New plan must enter reconcile before inspecting helper order")
        #expect(effects.plans == [original])
        effects.suspendReplace = false
        effects.finishReplace()
        await first.value
        await second.value
        #expect(effects.plans == [original, changed])
        #expect(subject.status == .scheduled)
    }

    @MainActor
    private final class Effects {
        var calls: [String] = []
        var plans: [SunriseWakePlan] = []
        var deadlines: [Date] = []
        var failure: SunriseWakeCoordinator.HelperFailure?
        var cancelFailure: SunriseWakeCoordinator.HelperFailure?
        var failCleanup = false
        var suspendReplace = false
        var secondaryReconcileStarted = false
        var continuation: CheckedContinuation<Void, Never>?
        lazy var delivery = SunriseDisplayDelivery(
            declareUserActivity: { self.calls.append("activity") },
            acquireDisplayAssertion: { deadline in
                self.calls.append("acquire")
                self.deadlines.append(deadline)
                return .init(rawValue: 41)
            },
            releaseDisplayAssertion: { _ in self.calls.append("release") }
        )

        func subject() -> SunriseWakeCoordinator {
            SunriseWakeCoordinator(
                operations: .init(replace: { plan in
                    self.calls.append("replace")
                    self.plans.append(plan)
                    if self.suspendReplace {
                        await withCheckedContinuation { self.continuation = $0 }
                    }
                    if let failure = self.failure {
                        throw failure
                    }
                }, cancel: {
                    self.calls.append("cancel")
                    if let failure = self.cancelFailure {
                        throw failure
                    }
                }),
                displayDelivery: delivery,
                cleanupNativeAssertions: {
                    self.calls.append("cleanup")
                    if self.failCleanup {
                        throw SunriseWakeCoordinator.HelperFailure.rejected
                    }
                }
            )
        }

        func waitForSuspendedReplace() async -> Bool {
            for _ in 0 ..< 100 {
                if continuation != nil {
                    return true
                }
                await Task.yield()
            }
            return false
        }

        /// Both tasks share MainActor: observing the flag occurs after the caller
        /// has entered reconcile and yielded or returned, not before the call.
        func waitForSecondaryReconcile() async -> Bool {
            for _ in 0 ..< 100 {
                if secondaryReconcileStarted {
                    return true
                }
                await Task.yield()
            }
            return false
        }

        func finishReplace() {
            continuation?.resume()
            continuation = nil
        }
    }
}
