@testable import CurfewKit
import Foundation
import Testing

/// Exercises the real helper service after its signed-client boundary. Direct
/// calls do not prove installed XPC signature authentication or physical wake.
struct SunriseScheduleIndependenceTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let owner = "studio.hypertext.curfew.dev.sunrise"

    @Test func futureScheduledSunriseDoesNotRequireOrCreateEnforcement() async throws {
        let fixture = try fixture(activeRecord: nil)
        defer { fixture.remove() }
        let originalState = try Data(contentsOf: fixture.store.stateURL)

        let result = try await replace(fixture, plan: fixture.plan)

        #expect(result.0 != nil)
        #expect(result.1 == nil)
        #expect(fixture.effects.scheduled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.record == .init(plan: fixture.plan, phase: .scheduled))
        #expect(fixture.effects.cancelled.isEmpty)
        let status = await fixture.service.evaluateNow()
        #expect(status.activeRecord == nil)
        #expect(try fixture.store.load()?.activeRecord == nil)
        #expect(try Data(contentsOf: fixture.store.stateURL) == originalState)
    }

    @Test func accountWakeAuthorityDoesNotMoveOrRejectScheduledSunrise() async throws {
        let restriction = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-3600),
            scheduledUnlockAt: .distantFuture,
            kind: .accountWakeCampaign,
            campaignID: UUID()
        )
        let fixture = try fixture(activeRecord: restriction)
        defer { fixture.remove() }
        let originalState = try Data(contentsOf: fixture.store.stateURL)
        let scheduledUnlock = fixture.plan.holdUntil.addingTimeInterval(-300)
        #expect(fixture.plan.occurrenceID != restriction.lockoutID)

        let result = try await replace(fixture, plan: fixture.plan)

        #expect(result.0 != nil)
        #expect(result.1 == nil)
        #expect(fixture.effects.scheduled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.scheduled.first?.wakeAt == scheduledUnlock
            .addingTimeInterval(-1800))
        #expect(fixture.effects.record == .init(plan: fixture.plan, phase: .scheduled))
        #expect(fixture.effects.cancelled.isEmpty)
        let status = await fixture.service.evaluateNow()
        #expect(status.activeRecord == restriction)
        #expect(try fixture.store.load()?.activeRecord == restriction)
        #expect(try Data(contentsOf: fixture.store.stateURL) == originalState)
    }

    @Test func invalidBoundedIntervalsRejectBeforeAnySchedulingEffect() async throws {
        let fixture = try fixture(activeRecord: nil)
        defer { fixture.remove() }
        let originalState = try Data(contentsOf: fixture.store.stateURL)
        // Includes just outside the 5...60 minute lead plus five-minute hold,
        // and a fractional-minute lead inside the otherwise valid interval.
        for interval in [TimeInterval(599), 3901, 2101] {
            let plan = SunriseWakePlan(
                owner: owner, occurrenceID: fixture.plan.occurrenceID,
                wakeAt: fixture.plan.wakeAt,
                holdUntil: fixture.plan.wakeAt.addingTimeInterval(interval),
                allowsBattery: false
            )
            let result = try await replace(fixture, plan: plan)
            #expect(result.0 == nil)
            #expect(result.1 != nil)
        }
        expectNoEffects(fixture.effects)
        #expect(try Data(contentsOf: fixture.store.stateURL) == originalState)
    }

    @Test func foreignOwnerRejectsBeforeAnySchedulingEffect() async throws {
        let fixture = try fixture(activeRecord: nil)
        defer { fixture.remove() }
        let plan = SunriseWakePlan(
            owner: "foreign", occurrenceID: fixture.plan.occurrenceID,
            wakeAt: fixture.plan.wakeAt, holdUntil: fixture.plan.holdUntil,
            allowsBattery: false
        )
        let originalState = try Data(contentsOf: fixture.store.stateURL)
        let result = try await replace(fixture, plan: plan)
        #expect(result.0 == nil)
        #expect(result.1 != nil)
        expectNoEffects(fixture.effects)
        #expect(try Data(contentsOf: fixture.store.stateURL) == originalState)
    }

    private func expectNoEffects(_ effects: Effects) {
        #expect(effects.loads == 0)
        #expect(effects.saves == 0)
        #expect(effects.record == nil)
        #expect(effects.scheduled.isEmpty)
        #expect(effects.cancelled.isEmpty)
    }

    private func fixture(activeRecord: LockoutDeadlineRecord?) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = PrivilegedDaemonStateStore(stateURL: directory
            .appendingPathComponent("state.json"))
        try store.saveControl(AuthenticatedDaemonControl(persisted: PrivilegedDaemonStatus(
            activeRecord: activeRecord, lastHeartbeatAt: now, shutdownIssued: false
        )))
        let effects = Effects()
        let scheduler = SunriseWakeScheduler(
            owner: owner,
            load: { effects.loads += 1; return effects.record },
            save: { effects.saves += 1; effects.record = $0 },
            schedule: { effects.scheduled.append($0) },
            cancel: { effects.cancelled.append($0) }
        )
        let service = AuthenticatedDaemonService(
            store: store, readExternal: { _, _ in nil }, evaluate: { _, _, _ in false },
            discover: {}, sunriseScheduler: scheduler, sunriseOwner: owner,
            sunriseNow: { now }, sunriseOnExternalPower: { true }
        )
        let plan = SunriseWakePlan(
            owner: owner, occurrenceID: UUID(),
            wakeAt: now.addingTimeInterval(1800), holdUntil: now.addingTimeInterval(3900),
            allowsBattery: false
        )
        return Fixture(
            service: service,
            effects: effects,
            plan: plan,
            store: store,
            directory: directory
        )
    }

    private func replace(
        _ fixture: Fixture,
        plan: SunriseWakePlan
    ) async throws -> (Data?, NSError?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let request = try encoder.encode(plan)
        return await withCheckedContinuation { continuation in
            fixture.service.replaceSunriseWakePlan(request) {
                continuation.resume(returning: ($0, $1))
            }
        }
    }

    private struct Fixture {
        let service: AuthenticatedDaemonService
        let effects: Effects
        let plan: SunriseWakePlan
        let store: PrivilegedDaemonStateStore
        let directory: URL
        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class Effects {
        var record: SunriseWakeScheduler.Record?
        var loads = 0
        var saves = 0
        var scheduled: [SunriseWakeScheduler.Event] = []
        var cancelled: [SunriseWakeScheduler.Event] = []
    }
}
