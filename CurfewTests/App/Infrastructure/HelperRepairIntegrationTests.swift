@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct HelperRepairIntegrationTests {
    @Test("Installation finishes by verifying the connection, without a second action")
    func installationChecksConnection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let heartbeat = root.appendingPathComponent("heartbeat")
        try Data("alive".utf8).write(to: heartbeat)
        let daemon = StubAppService(status: .notRegistered)
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered),
            daemonHeartbeatURL: heartbeat,
            daemonRPC: StubDaemonRPC(statusResult: .success(PrivilegedDaemonStatus(
                activeRecord: nil, lastHeartbeatAt: nil, shutdownIssued: false
            )))
        )
        await manager.installAndConnectDaemon()
        #expect(manager.connectionState == .ready)
        #expect(daemon.registerCallCount == 1)
        #expect(daemon.unregisterCallCount == 0)
    }

    @Test("New arming cannot race asynchronous repair admission")
    func repairAdmissionPreventsNewArming() async {
        let rpc = StubDaemonRPC(statusResult: .failure(PrivilegedDaemonRPCError.unavailable))
        let daemon = StubAppService(status: .enabled)
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: rpc
        )
        await manager.reconnectBackgroundProtection(
            quiesce: {},
            legacyAdmission: {
                await manager.armLockout(LockoutDeadlineRecord(
                    lockoutStartedAt: Date(),
                    scheduledUnlockAt: Date().addingTimeInterval(600),
                    kind: .scheduledTime
                ))
                throw PrivilegedEnforcementError.activeLockout
            },
            contextIsCurrent: { true },
            resume: {}
        )
        #expect(rpc.armCallCount == 0)
        #expect(daemon.unregisterCallCount == 0)
        #expect(!manager.maintenancePaused)
    }

    @Test("Refusing repair preserves enforcement and does not stop producers")
    func refusedRepairPreservesEnforcement() async {
        let daemon = StubAppService(status: .enabled)
        let manager = PrivilegedHelperManager(
            daemonService: daemon,
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: StubDaemonRPC(statusResult: .failure(PrivilegedEnforcementError
                    .activeLockout))
        )
        var stopped = false
        await manager.reconnectBackgroundProtection(
            quiesce: { stopped = true },
            legacyAdmission: { Issue.record("Unexpected legacy admission") },
            contextIsCurrent: { true },
            resume: { Issue.record("Unexpected resume") }
        )
        #expect(!stopped)
        #expect(!manager.maintenancePaused)
        #expect(daemon.unregisterCallCount == 0)
        #expect(daemon.registerCallCount == 0)
    }
}
