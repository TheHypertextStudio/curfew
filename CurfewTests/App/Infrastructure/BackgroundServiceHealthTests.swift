@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct BackgroundServiceHealthTests {
    @Test func correctionsWithinPollThrottleCannotRefillStartupGrace() {
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: SupervisorHealthStore(),
            retireLegacyGuard: {}
        )
        let start = Date(timeIntervalSince1970: 10000)
        manager.refreshSupervisorHealthIfNeeded(at: start)
        for _ in 0 ..< 30 {
            manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(4))
            manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(1))
        }
        #expect(manager.supervisorHealthError != nil)
    }

    @Test func clockCorrectionPreservesRemainingPollDelay() throws {
        let store = SupervisorHealthStore()
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: store, retireLegacyGuard: {}
        )
        let start = Date(timeIntervalSince1970: 10000)
        manager.refreshSupervisorHealthIfNeeded(at: start)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(4))
        let receipt = start.addingTimeInterval(1)
        try store.save(SupervisorHealthRecord(lastCheckedAt: receipt))
        manager.refreshSupervisorHealthIfNeeded(at: receipt)
        #expect(manager.supervisorLastCheckedAt == nil)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(2))
        #expect(manager.supervisorLastCheckedAt == receipt)
        #expect(manager.isRecoveryHealthy)
    }

    @Test func backwardClockPreservesRemainingMissingHeartbeatGrace() {
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: SupervisorHealthStore(),
            retireLegacyGuard: {}
        )
        let start = Date(timeIntervalSince1970: 10000)
        manager.refreshSupervisorHealthIfNeeded(at: start)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(40))
        let corrected = start.addingTimeInterval(-3600)
        manager.refreshSupervisorHealthIfNeeded(at: corrected)
        manager.refreshSupervisorHealthIfNeeded(at: corrected.addingTimeInterval(45))
        #expect(manager.supervisorHealthError == nil)
        manager.refreshSupervisorHealthIfNeeded(at: corrected.addingTimeInterval(50))
        #expect(manager.supervisorHealthError != nil)
    }

    @Test func backwardClockCannotRestoreExpiredMissingHeartbeatGrace() {
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: SupervisorHealthStore(),
            retireLegacyGuard: {}
        )
        let start = Date(timeIntervalSince1970: 10000)
        manager.refreshSupervisorHealthIfNeeded(at: start)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(90))
        #expect(manager.supervisorHealthError != nil)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(-3600))
        #expect(manager.supervisorHealthError != nil)
    }

    @Test func repeatedBackwardCorrectionsDoNotRefillMissingHeartbeatGrace() {
        let manager = BackgroundServiceManager(
            service: HealthServiceStub(), healthStore: SupervisorHealthStore(),
            retireLegacyGuard: {}
        )
        let start = Date(timeIntervalSince1970: 10000)
        manager.refreshSupervisorHealthIfNeeded(at: start)
        manager.refreshSupervisorHealthIfNeeded(at: start.addingTimeInterval(30))
        let firstCorrection = start.addingTimeInterval(-3600)
        manager.refreshSupervisorHealthIfNeeded(at: firstCorrection)
        manager.refreshSupervisorHealthIfNeeded(at: firstCorrection.addingTimeInterval(30))
        let secondCorrection = firstCorrection.addingTimeInterval(-3600)
        manager.refreshSupervisorHealthIfNeeded(at: secondCorrection)
        manager.refreshSupervisorHealthIfNeeded(at: secondCorrection.addingTimeInterval(25))
        #expect(manager.supervisorHealthError == nil)
        manager.refreshSupervisorHealthIfNeeded(at: secondCorrection.addingTimeInterval(30))
        #expect(manager.supervisorHealthError != nil)
    }

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
