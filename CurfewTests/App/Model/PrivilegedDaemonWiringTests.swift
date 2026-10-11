@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct PrivilegedDaemonWiringTests {
    @Test("Daemon relaunch status replaces a weaker local lockout deadline")
    func daemonStatusOverridesWeakerLocalDeadline() async throws {
        let now = Date()
        let local = makeRecord(now: now, duration: 120)
        let authoritative = makeRecord(now: now, duration: 600)
        let (model, rpc) = makeModel(record: authoritative, now: now)
        model.lockoutDeadlineStore.save(local)

        await model.reconcilePrivilegedDaemonState()

        let persisted = try #require(model.lockoutDeadlineStore.load())
        #expect(persisted.lockoutID == authoritative.lockoutID)
        #expect(
            abs(persisted.scheduledUnlockAt.timeIntervalSince(authoritative.scheduledUnlockAt)) < 1
        )
        #expect(rpc.heartbeatIDs == [authoritative.lockoutID])
    }

    @Test("Active lockout heartbeat is sent at a bounded cadence")
    func activeLockoutHeartbeatIsThrottled() async {
        let now = Date()
        let record = makeRecord(now: now, duration: 600)
        let (model, rpc) = makeModel(record: record, now: now)
        model.lockoutDeadlineStore.save(record)

        model.currentTime = now
        model.touchAppHeartbeat()
        await Task.yield()
        model.currentTime = now.addingTimeInterval(1)
        model.touchAppHeartbeat()
        await Task.yield()
        #expect(rpc.heartbeatIDs == [record.lockoutID])

        model.currentTime = now.addingTimeInterval(30)
        model.touchAppHeartbeat()
        await Task.yield()
        #expect(rpc.heartbeatIDs == [record.lockoutID, record.lockoutID])
    }

    private func makeRecord(now: Date, duration: TimeInterval) -> LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-60),
            scheduledUnlockAt: now.addingTimeInterval(duration),
            kind: .scheduledTime
        )
    }

    private func makeModel(
        record: LockoutDeadlineRecord,
        now: Date
    ) -> (CurfewAppModel, ModelDaemonRPC) {
        let rpc = ModelDaemonRPC(status: PrivilegedDaemonStatus(
            activeRecord: record,
            lastHeartbeatAt: now,
            shutdownIssued: false
        ))
        let helper = PrivilegedHelperManager(
            daemonService: ModelAppService(status: .enabled),
            loginItemService: ModelAppService(status: .notRegistered),
            daemonRPC: rpc
        )
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            featureFlags: .shippingV1,
            activityRecorder: NullActivityRecording(),
            privilegedHelperManager: helper,
            idleWatcher: IdleWatcher(source: ZeroIdleSource()),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        return (model, rpc)
    }
}

private final class ModelDaemonRPC: PrivilegedDaemonRPCControlling, @unchecked Sendable {
    let daemonStatus: PrivilegedDaemonStatus
    private(set) var heartbeatIDs: [UUID] = []

    init(status: PrivilegedDaemonStatus) {
        self.daemonStatus = status
    }

    func armLockout(_: LockoutDeadlineRecord) async throws {}
    func heartbeat(lockoutID: UUID) async throws {
        heartbeatIDs.append(lockoutID)
    }

    func completeLockout(lockoutID _: UUID, reason _: PrivilegedCompletionReason) async throws {}
    func status() async throws -> PrivilegedDaemonStatus {
        daemonStatus
    }

    func prepareForUninstall() async throws {}
}

private final class ModelAppService: AppServiceControlling {
    var status: SMAppService.Status

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {}
    func unregister() throws {}
}

private final class ZeroIdleSource: IdleTimeSource {
    func secondsSinceLastInput() -> TimeInterval {
        0
    }
}
