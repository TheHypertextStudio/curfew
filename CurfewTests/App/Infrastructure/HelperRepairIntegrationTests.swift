@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct HelperRepairIntegrationTests {
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
