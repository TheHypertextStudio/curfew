@testable import CurfewKit
import Foundation
import Testing

/// Contract preparation only: these behavioral tests have not been executed.
/// All effects are in-memory; no native power API or helper connection runs.
struct SunriseWakeSchedulerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let owner = "studio.hypertext.curfew.dev.sunrise"
    private let occurrenceID = UUID()

    private func plan(offset: TimeInterval = 1800) -> SunriseWakePlan {
        SunriseWakePlan(
            owner: owner, occurrenceID: occurrenceID,
            wakeAt: now.addingTimeInterval(offset),
            holdUntil: now.addingTimeInterval(3900), allowsBattery: false
        )
    }

    private func scheduler(_ effects: Effects) -> SunriseWakeScheduler {
        SunriseWakeScheduler(
            owner: owner,
            load: { effects.record },
            save: { record in
                effects.saveAttempts += 1
                if effects.rejectSave || effects.saveAttempts == effects.rejectSaveAttempt {
                    throw Failure.rejected
                }
                effects.record = record
                effects.calls.append("save")
            },
            schedule: { event in
                effects.calls.append("schedule")
                effects.scheduled.append(event)
                if effects.rejectSchedule {
                    throw Failure.rejected
                }
            },
            cancel: { event in
                effects.calls.append("cancel")
                effects.cancelled.append(event)
                if effects.rejectCancel {
                    throw Failure.rejected
                }
            }
        )
    }

    private func apply(
        _ scheduler: SunriseWakeScheduler, desired: SunriseWakePlan?
    ) throws -> SunriseWakeScheduler.Outcome {
        try scheduler.reconcile(
            desired: desired, authorizedPlan: desired,
            onExternalPower: true, now: now
        )
    }

    @Test("Persist cancellation identity before requesting one fixed wake event")
    func persistsBeforeScheduling() throws {
        let effects = Effects()
        #expect(try apply(scheduler(effects), desired: plan()) == .scheduled)
        #expect(effects.calls == ["save", "schedule", "save"])
        let event = try #require(effects.scheduled.first)
        #expect(event.owner == owner)
        #expect(event.eventType == "wake")
        #expect(event.wakeAt == plan().wakeAt)
        #expect(effects.record?.phase == .scheduled)
    }

    @Test("Replacement cancels exact old identity before storing and scheduling new event")
    func replacesOwnedEvent() throws {
        let old = plan()
        let effects = Effects(record: .init(plan: old, phase: .scheduled))
        #expect(try apply(scheduler(effects), desired: plan(offset: 2400)) == .scheduled)
        #expect(effects.calls == ["cancel", "save", "schedule", "save"])
        #expect(effects.cancelled == [.init(plan: old)])
    }

    @Test("Repeated accepted plan does not duplicate a native request")
    func deduplicatesWithinProcess() throws {
        let effects = Effects()
        let subject = scheduler(effects)
        _ = try apply(subject, desired: plan())
        effects.calls = []
        #expect(try apply(subject, desired: plan()) == .unchanged)
        #expect(effects.calls.isEmpty)
    }

    @Test("Disable cancels only the journaled owned event then clears the journal")
    func disables() throws {
        let old = plan()
        let effects = Effects(record: .init(plan: old, phase: .scheduled))
        #expect(try apply(scheduler(effects), desired: nil) == .cancelled)
        #expect(effects.cancelled == [.init(plan: old)])
        #expect(effects.record == nil)
    }

    @Test("Native rejection retains identity for recovery without reporting scheduled")
    func rejectionRemainsRecoverable() throws {
        let effects = Effects()
        effects.rejectSchedule = true
        #expect(throws: Failure.rejected) {
            try apply(scheduler(effects), desired: plan())
        }
        #expect(effects.record?.plan == plan())
        #expect(effects.record?.phase == .pending)
    }

    @Test("Journal failure prevents an untracked native event")
    func persistenceFailureHasNoNativeEffect() throws {
        let effects = Effects()
        effects.rejectSave = true
        #expect(throws: Failure.rejected) {
            try apply(scheduler(effects), desired: plan())
        }
        #expect(effects.scheduled.isEmpty)
    }

    @Test("Failed final journal save retains pending identity after native acceptance")
    func finalSaveFailureRetainsRecoveryIdentity() throws {
        let effects = Effects()
        effects.rejectSaveAttempt = 2
        #expect(throws: Failure.rejected) {
            try apply(scheduler(effects), desired: plan())
        }
        #expect(effects.scheduled == [.init(plan: plan())])
        #expect(effects.record == .init(plan: plan(), phase: .pending))

        effects.rejectSaveAttempt = nil
        effects.calls = []
        #expect(try apply(scheduler(effects), desired: plan()) == .scheduled)
        #expect(effects.calls == ["cancel", "save", "schedule", "save"])
    }

    @Test("Failed cancellation retains old identity and blocks replacement")
    func cancellationFailureBlocksReplacement() throws {
        let old = plan()
        let effects = Effects(record: .init(plan: old, phase: .scheduled))
        effects.rejectCancel = true
        #expect(throws: Failure.rejected) {
            try apply(scheduler(effects), desired: plan(offset: 2400))
        }
        #expect(effects.record?.plan == old)
        #expect(effects.scheduled.isEmpty)
    }

    @Test("Restart treats even a scheduled journal as unknown native state")
    func recoversUnknownNativeState() throws {
        for phase in [SunriseWakeScheduler.Record.Phase.pending, .scheduled] {
            let effects = Effects(record: .init(plan: plan(), phase: phase))
            #expect(try apply(scheduler(effects), desired: plan()) == .scheduled)
            #expect(effects.calls == ["cancel", "save", "schedule", "save"])
            #expect(effects.cancelled == [.init(plan: plan())])
        }
    }

    @Test("Decoded request must equal a fresh helper-authorized plan")
    func revalidatesDecodedPlan() throws {
        let encoded = try JSONEncoder().encode(plan(offset: 2400))
        let decoded = try JSONDecoder().decode(SunriseWakePlan.self, from: encoded)
        let effects = Effects()
        #expect(throws: SunriseWakeScheduler.Rejection.unauthorizedPlan) {
            try scheduler(effects).reconcile(
                desired: decoded, authorizedPlan: plan(), onExternalPower: true, now: now
            )
        }
        #expect(effects.calls.isEmpty)
    }

    @Test("Battery exclusion prevents scheduling even a matching authorized plan")
    func rejectsBattery() throws {
        let effects = Effects()
        #expect(throws: SunriseWakeScheduler.Rejection.batteryExcluded) {
            try scheduler(effects).reconcile(
                desired: plan(), authorizedPlan: plan(), onExternalPower: false, now: now
            )
        }
        #expect(effects.scheduled.isEmpty)
    }

    @Test("Battery transition cancels recovered AC-only identity before rejecting")
    func batteryTransitionCancelsRecoveredPlan() throws {
        for phase in [SunriseWakeScheduler.Record.Phase.pending, .scheduled] {
            let effects = Effects(record: .init(plan: plan(), phase: phase))
            #expect(throws: SunriseWakeScheduler.Rejection.batteryExcluded) {
                try scheduler(effects).reconcile(
                    desired: plan(), authorizedPlan: plan(), onExternalPower: false, now: now
                )
            }
            #expect(effects.calls == ["cancel", "save"])
            #expect(effects.cancelled == [.init(plan: plan())])
            #expect(effects.record == nil)
            #expect(effects.scheduled.isEmpty)
        }
    }

    @Test("Battery transition cancels in-process accepted AC-only wake before rejecting")
    func batteryTransitionCancelsAcceptedPlan() throws {
        let effects = Effects()
        let subject = scheduler(effects)
        _ = try apply(subject, desired: plan())
        effects.calls = []
        effects.scheduled = []
        #expect(throws: SunriseWakeScheduler.Rejection.batteryExcluded) {
            try subject.reconcile(
                desired: plan(), authorizedPlan: plan(), onExternalPower: false, now: now
            )
        }
        #expect(effects.calls == ["cancel", "save"])
        #expect(effects.cancelled == [.init(plan: plan())])
        #expect(effects.record == nil)
        #expect(effects.scheduled.isEmpty)
    }

    @Test("Unauthorized battery request cannot cancel a previously owned event")
    func unauthorizedBatteryRequestHasNoEffects() throws {
        let record = SunriseWakeScheduler.Record(plan: plan(), phase: .scheduled)
        let effects = Effects(record: record)
        #expect(throws: SunriseWakeScheduler.Rejection.unauthorizedPlan) {
            try scheduler(effects).reconcile(
                desired: plan(offset: 2400), authorizedPlan: plan(),
                onExternalPower: false, now: now
            )
        }
        #expect(effects.calls.isEmpty)
        #expect(effects.record == record)
        #expect(effects.cancelled.isEmpty)
        #expect(effects.scheduled.isEmpty)
    }

    @Test("Foreign journal never authorizes cancelling another owner's event")
    func rejectsForeignJournal() throws {
        let foreign = SunriseWakePlan(
            owner: "other.app", occurrenceID: occurrenceID,
            wakeAt: plan().wakeAt, holdUntil: plan().holdUntil, allowsBattery: false
        )
        let effects = Effects(record: .init(plan: foreign, phase: .pending))
        #expect(throws: SunriseWakeScheduler.Rejection.foreignOwner) {
            try apply(scheduler(effects), desired: nil)
        }
        #expect(effects.cancelled.isEmpty)
    }

    @Test("Matching authority does not admit an elapsed wake timestamp")
    func rejectsExpiredPlan() throws {
        let effects = Effects()
        #expect(throws: SunriseWakeScheduler.Rejection.expired) {
            try apply(scheduler(effects), desired: plan(offset: -1))
        }
        #expect(effects.calls.isEmpty)
    }

    @Test("Matching authority does not admit nonfinite or inverted timestamps")
    func rejectsInvalidTimestamps() throws {
        let invalid = [
            SunriseWakePlan(
                owner: owner, occurrenceID: occurrenceID,
                wakeAt: Date(timeIntervalSince1970: .infinity),
                holdUntil: plan().holdUntil, allowsBattery: false
            ),
            SunriseWakePlan(
                owner: owner, occurrenceID: occurrenceID,
                wakeAt: plan().wakeAt,
                holdUntil: now.addingTimeInterval(900), allowsBattery: false
            )
        ]
        for candidate in invalid {
            let effects = Effects()
            #expect(throws: SunriseWakeScheduler.Rejection.invalidTimestamp) {
                try apply(scheduler(effects), desired: candidate)
            }
            #expect(effects.calls.isEmpty)
        }
    }

    private enum Failure: Error, Equatable { case rejected }

    private final class Effects {
        var record: SunriseWakeScheduler.Record?
        var calls: [String] = []
        var scheduled: [SunriseWakeScheduler.Event] = []
        var cancelled: [SunriseWakeScheduler.Event] = []
        var rejectSave = false
        var rejectSaveAttempt: Int?
        var saveAttempts = 0
        var rejectSchedule = false
        var rejectCancel = false

        init(record: SunriseWakeScheduler.Record? = nil) {
            self.record = record
        }
    }
}
