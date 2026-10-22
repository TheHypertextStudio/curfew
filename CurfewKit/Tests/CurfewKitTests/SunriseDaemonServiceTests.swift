@testable import CurfewKit
import Foundation
import Testing

/// Direct helper-boundary contracts with in-memory power effects. These do not
/// establish that an installed XPC listener authenticates a real client.
struct SunriseDaemonServiceTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let owner = "studio.hypertext.curfew.dev.sunrise"

    @Test func validScheduledOccurrenceSchedulesExactOwnedWake() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let result = await replace(fixture.service, fixture.plan)
        #expect(result.1 == nil)
        #expect(result.0 != nil)
        #expect(fixture.effects.scheduled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
    }

    @Test func strongerExternalRestrictionDoesNotShiftScheduledSunrise() async throws {
        let fixture = try fixture(strongerExternal: true)
        defer { fixture.remove() }
        let result = await replace(fixture.service, fixture.plan)
        #expect(result.1 == nil)
        #expect(fixture.effects.scheduled.first?.wakeAt == fixture.plan.wakeAt)
        let status = await fixture.service.evaluateNow()
        #expect(status.activeRecord?.kind == .remoteCommand)
        #expect(status.activeRecord?.scheduledUnlockAt == now.addingTimeInterval(7200))
    }

    @Test func invalidRequestsRejectBeforeJournalOrNativeEffects() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let valid = fixture.plan
        let rejected = try [
            Data("not-json".utf8),
            Data(repeating: 32, count: 4097),
            encode(SunriseWakePlan(
                owner: "foreign",
                occurrenceID: valid.occurrenceID,
                wakeAt: valid.wakeAt,
                holdUntil: valid.holdUntil,
                allowsBattery: false
            )),
            encode(SunriseWakePlan(
                owner: owner,
                occurrenceID: UUID(),
                wakeAt: valid.wakeAt,
                holdUntil: valid.holdUntil,
                allowsBattery: false
            )),
            encode(SunriseWakePlan(
                owner: owner,
                occurrenceID: valid.occurrenceID,
                wakeAt: now.addingTimeInterval(1),
                holdUntil: valid.holdUntil,
                allowsBattery: false
            )),
            encode(SunriseWakePlan(
                owner: owner,
                occurrenceID: valid.occurrenceID,
                wakeAt: valid.wakeAt,
                holdUntil: valid.holdUntil.addingTimeInterval(1),
                allowsBattery: false
            ))
        ]
        for request in rejected {
            let result = await rpc { fixture.service.replaceSunriseWakePlan(request, reply: $0) }
            #expect(result.0 == nil)
            #expect(result.1 != nil)
        }
        #expect(fixture.effects.loads == 0)
        #expect(fixture.effects.saves == 0)
        #expect(fixture.effects.scheduled.isEmpty)
        #expect(fixture.effects.cancelled.isEmpty)
    }

    @Test func nonScheduledLocalOccurrenceCannotAuthorizeWake() async throws {
        let fixture = try fixture(kind: .accountWakeCampaign)
        defer { fixture.remove() }
        let result = await replace(fixture.service, fixture.plan)
        #expect(result.1 != nil)
        #expect(fixture.effects.loads == 0)
        #expect(fixture.effects.scheduled.isEmpty)
    }

    @Test func cancellationCancelsExactOwnedIdentity() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.effects.record = .init(plan: fixture.plan, phase: .scheduled)
        let result = await rpc { fixture.service.cancelSunriseWakePlan(reply: $0) }
        #expect(result.1 == nil)
        #expect(fixture.effects.cancelled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.record == nil)
    }

    @Test func permittedUninstallCancelsOwnedWakeBeforeClearingState() async throws {
        let fixture = try fixture(expired: true)
        defer { fixture.remove() }
        fixture.effects.record = .init(plan: fixture.plan, phase: .scheduled)
        let result = await rpc { fixture.service.prepareForUninstall(reply: $0) }
        #expect(result.1 == nil)
        #expect(fixture.effects.cancelled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.stateExistsDuringCancellation == [true])
        #expect(fixture.effects.record == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.stateURL.path))
    }

    @Test func uninstallCancellationFailureRetainsStateAndOwnedJournal() async throws {
        let fixture = try fixture(expired: true)
        defer { fixture.remove() }
        let journal = SunriseWakeScheduler.Record(plan: fixture.plan, phase: .scheduled)
        fixture.effects.record = journal
        fixture.effects.cancellationError = NSError(domain: "SunriseCancelFixture", code: 73)
        let originalState = try Data(contentsOf: fixture.store.stateURL)
        let result = await rpc { fixture.service.prepareForUninstall(reply: $0) }
        #expect(result.0 == nil)
        #expect(result.1?.domain == "SunriseCancelFixture")
        #expect(result.1?.code == 73)
        #expect(fixture.effects.cancelled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.stateExistsDuringCancellation == [true])
        #expect(fixture.effects.record == journal)
        #expect(try Data(contentsOf: fixture.store.stateURL) == originalState)
    }

    @Test func nativeSchedulingErrorIsReturnedWithoutSuccess() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        fixture.effects.nativeError = NSError(domain: "SunriseNativeFixture", code: 42)
        let result = await replace(fixture.service, fixture.plan)
        #expect(result.0 == nil)
        #expect(result.1?.domain == "SunriseNativeFixture")
        #expect(result.1?.code == 42)
        #expect(fixture.effects.record?.phase == .pending)
    }

    @Test func batteryRecheckCancelsOwnedACOnlyEvent() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let accepted = await replace(fixture.service, fixture.plan)
        #expect(accepted.1 == nil)
        fixture.effects.onExternalPower = false
        let rejected = await replace(fixture.service, fixture.plan)
        #expect(rejected.0 == nil)
        #expect(rejected.1 != nil)
        #expect(fixture.effects.scheduled.count == 1)
        #expect(fixture.effects.cancelled == [SunriseWakeScheduler.Event(plan: fixture.plan)])
        #expect(fixture.effects.record == nil)
    }

    private func fixture(
        strongerExternal: Bool = false,
        kind: LockoutKind = .scheduledTime,
        expired: Bool = false
    ) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = PrivilegedDaemonStateStore(stateURL: directory
            .appendingPathComponent("state.json"))
        // Uninstall currently checks the wall clock. A known-past occurrence
        // reaches cancellation regardless of the injected Sunrise fixture clock.
        let occurrenceReference = expired ? Date(timeIntervalSince1970: 3600) : now
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: occurrenceReference.addingTimeInterval(-3600),
            scheduledUnlockAt: occurrenceReference.addingTimeInterval(expired ? -1 : 3600),
            kind: kind
        )
        try store.saveControl(AuthenticatedDaemonControl(persisted: PrivilegedDaemonStatus(
            activeRecord: record, lastHeartbeatAt: now, shutdownIssued: false
        )))
        let plan = SunriseWakePlan(
            owner: owner,
            occurrenceID: record.lockoutID,
            wakeAt: now.addingTimeInterval(1800),
            holdUntil: now.addingTimeInterval(3900),
            allowsBattery: false
        )
        let effects = Effects()
        let scheduler = SunriseWakeScheduler(
            owner: owner,
            load: { effects.loads += 1; return effects.record },
            save: { effects.saves += 1; effects.record = $0 },
            schedule: {
                effects.scheduled.append($0)
                if let error = effects.nativeError {
                    throw error
                }
            },
            cancel: {
                effects.stateExistsDuringCancellation.append(
                    FileManager.default.fileExists(atPath: store.stateURL.path)
                )
                effects.cancelled.append($0)
                if let error = effects.cancellationError {
                    throw error
                }
            }
        )
        let external = strongerExternal ? LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-100),
            scheduledUnlockAt: now.addingTimeInterval(7200), kind: .remoteCommand
        ) : nil
        let service = AuthenticatedDaemonService(
            store: store, readExternal: { _, _ in external }, evaluate: { _, _, _ in false },
            discover: {}, sunriseScheduler: scheduler, sunriseOwner: owner,
            sunriseNow: { now }, sunriseOnExternalPower: { effects.onExternalPower }
        )
        return Fixture(
            service: service,
            effects: effects,
            plan: plan,
            store: store,
            directory: directory
        )
    }

    private func encode(_ plan: SunriseWakePlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(plan)
    }

    private func replace(
        _ service: AuthenticatedDaemonService,
        _ plan: SunriseWakePlan
    ) async -> (Data?, NSError?) {
        do {
            let request = try encode(plan)
            return await rpc { service.replaceSunriseWakePlan(request, reply: $0) }
        } catch { return (nil, error as NSError) }
    }

    private func rpc(_ operation: (@escaping (Data?, NSError?) -> Void) -> Void) async
        -> (Data?, NSError?) {
        await withCheckedContinuation { continuation in
            operation { continuation.resume(returning: ($0, $1)) }
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
        var stateExistsDuringCancellation: [Bool] = []
        var nativeError: NSError?
        var cancellationError: NSError?
        var onExternalPower = true
    }
}
