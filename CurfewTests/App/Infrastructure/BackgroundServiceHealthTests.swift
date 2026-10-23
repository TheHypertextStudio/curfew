@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct BackgroundServiceHealthTests {
    @Test func failedLaunchIsVisibleUntilAHealthyReconciliation() throws {
        let now = Date()
        let store = SupervisorHealthStore()
        try store.save(SupervisorHealthRecord(
            lastCheckedAt: now,
            launchFailure: "Launch Services rejected the app"
        ))
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: store, retireLegacyGuard: {}
        )
        manager.refreshStatus()
        #expect(manager.isEnabled)
        #expect(!manager.isRecoveryHealthy)
        #expect(manager.supervisorHealthError?.contains("Launch Services rejected the app") == true)
        try store.save(SupervisorHealthRecord(lastCheckedAt: now.addingTimeInterval(5)))
        manager.refreshSupervisorHealthIfNeeded(at: now.addingTimeInterval(6))
        #expect(manager.isRecoveryHealthy)
        #expect(manager.supervisorHealthError == nil)
    }

    @Test func staleSupervisorCannotClaimHealthyRecovery() throws {
        let store = SupervisorHealthStore()
        try store.save(SupervisorHealthRecord(lastCheckedAt: Date().addingTimeInterval(-90)))
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: store, retireLegacyGuard: {}
        )
        manager.refreshStatus()
        #expect(manager.isEnabled)
        #expect(!manager.isRecoveryHealthy)
        #expect(manager.supervisorHealthError?.contains("stopped checking in") == true)
    }

    @Test func missingHeartbeatHasStartupGraceAndReadsAreThrottled() throws {
        let store = SupervisorHealthStore()
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: store, retireLegacyGuard: {}
        )
        manager.refreshStatus()
        let now = Date()
        #expect(!manager.isRecoveryHealthy)
        #expect(manager.supervisorHealthError == nil)
        manager.refreshSupervisorHealthIfNeeded(at: now.addingTimeInterval(91))
        #expect(manager.supervisorHealthError != nil)
        try store.save(SupervisorHealthRecord(lastCheckedAt: now.addingTimeInterval(92)))
        manager.refreshSupervisorHealthIfNeeded(at: now.addingTimeInterval(92))
        #expect(!manager.isRecoveryHealthy)
        manager.refreshSupervisorHealthIfNeeded(at: now.addingTimeInterval(96))
        #expect(manager.isRecoveryHealthy)
    }
}

private struct HealthServiceStub: AppServiceControlling {
    var status: SMAppService.Status {
        .enabled
    }

    func register() throws {}
    func unregister() throws {}
}
