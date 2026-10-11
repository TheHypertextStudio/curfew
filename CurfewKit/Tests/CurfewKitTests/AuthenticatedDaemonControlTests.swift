@testable import CurfewKit
import Foundation
import Testing

struct AuthenticatedDaemonControlTests {
    let now = Date(timeIntervalSince1970: 1000)

    func record(
        kind: LockoutKind = .scheduledTime,
        duration: TimeInterval = 600
    ) -> LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(duration),
            kind: kind
        )
    }

    @Test func authenticatedLivenessCannotFallBackToTheLegacyFile() throws {
        var control = AuthenticatedDaemonControl()
        let deadline = record()
        #expect(!control.usesAuthenticatedHeartbeat(for: deadline, now: now))
        try control.arm(deadline, now: now)
        #expect(control.usesAuthenticatedHeartbeat(for: deadline, now: now.addingTimeInterval(120)))
        let restored = try JSONDecoder().decode(
            AuthenticatedDaemonControl.self, from: JSONEncoder().encode(control)
        )
        #expect(restored.usesAuthenticatedHeartbeat(for: deadline, now: now))
    }

    @Test func authenticatedRemoteHeartbeatIsBoundToItsWindow() throws {
        var control = AuthenticatedDaemonControl()
        let remote = record(kind: .remoteCommand)
        try control.heartbeat(lockoutID: remote.lockoutID, external: remote, now: now)
        #expect(control.usesAuthenticatedHeartbeat(for: remote, now: now))
        #expect(!control.usesAuthenticatedHeartbeat(for: record(), now: now))
    }

    @Test func aStrongerRemoteDeadlineStillAcceptsTheOwnedLocalHeartbeat() throws {
        var control = AuthenticatedDaemonControl()
        let local = record()
        let remote = record(kind: .remoteCommand, duration: 1200)
        try control.arm(local, now: now)
        try control.heartbeat(lockoutID: local.lockoutID, external: remote, now: now)
        #expect(control.status(external: remote, shutdownIssued: false, now: now)
            .activeRecord?.lockoutID == remote.lockoutID)
        #expect(throws: PrivilegedEnforcementError.lockoutMismatch) {
            try control.heartbeat(lockoutID: UUID(), external: remote, now: now)
        }
    }

    @Test func aReleasedWakeCannotReturnThroughTheFileBackend() throws {
        var control = AuthenticatedDaemonControl()
        let wake = record(kind: .accountWakeCampaign)
        try control.arm(wake, now: now)
        try control.complete(lockoutID: wake.lockoutID, reason: .accountWakeRelease, now: now)
        #expect(control.status(external: wake, shutdownIssued: false, now: now).activeRecord == nil)
        #expect(throws: PrivilegedEnforcementError.noActiveLockout) {
            try control.arm(wake, now: now)
        }
    }

    @Test func releasedAuthorityStaysReleasedAcrossDaemonRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PrivilegedDaemonStateStore(stateURL: directory
            .appendingPathComponent("state.json"))
        var control = AuthenticatedDaemonControl()
        let wake = record(kind: .accountWakeCampaign)
        try control.arm(wake, now: now)
        try control.complete(lockoutID: wake.lockoutID, reason: .accountWakeRelease, now: now)
        try store.saveControl(control)
        let loaded = try store.loadControl()
        let restored = try #require(loaded)
        #expect(restored.status(external: wake, shutdownIssued: false, now: now)
            .activeRecord == nil)
        let remote = record(kind: .remoteCommand)
        #expect(restored.status(external: remote, shutdownIssued: false, now: now)
            .activeRecord == remote)
    }

    @Test func uninstallCannotIgnoreIndependentRemoteAuthority() {
        let control = AuthenticatedDaemonControl()
        #expect(throws: PrivilegedEnforcementError.activeLockout) {
            try control.prepareForUninstall(external: record(kind: .remoteCommand), now: now)
        }
    }

    @Test func authenticatedWakeReleaseAlsoCoversLegacyRootShadow() throws {
        var control = AuthenticatedDaemonControl()
        let wake = record(kind: .accountWakeCampaign)
        try control.complete(
            lockoutID: wake.lockoutID,
            reason: .accountWakeRelease,
            now: now,
            external: wake
        )
        #expect(control.status(external: wake, shutdownIssued: false, now: now).activeRecord == nil)
    }

    @Test func wakeCompletionCanBeRetriedAfterItsReplyWasLost() throws {
        var control = AuthenticatedDaemonControl()
        let wake = record(kind: .accountWakeCampaign)
        try control.arm(wake, now: now)
        try control.complete(lockoutID: wake.lockoutID, reason: .accountWakeRelease, now: now)
        try control.complete(lockoutID: wake.lockoutID, reason: .accountWakeRelease, now: now)
        #expect(control.localStatus.activeRecord == nil)
    }

    @Test func anOverrideCannotRemoveDurableAuthority() throws {
        let deadline = record()
        var control = AuthenticatedDaemonControl()
        try control.arm(deadline, now: now)
        #expect(throws: PrivilegedEnforcementError.activeLockout) {
            try control.complete(lockoutID: deadline.lockoutID, reason: .approvedOverride, now: now)
        }
        #expect(control.localStatus.activeRecord == deadline)
    }

    @Test func armCannotShortenAnExistingWindow() throws {
        var deadline = record()
        var control = AuthenticatedDaemonControl()
        try control.arm(deadline, now: now)
        deadline.scheduledUnlockAt = now.addingTimeInterval(60)
        try control.arm(deadline, now: now)
        #expect(control.localStatus.activeRecord?.scheduledUnlockAt == now.addingTimeInterval(600))
    }

    @Test func localCompletionPreservesRemoteSource() throws {
        let local = record(duration: 30)
        let remote = record(kind: .remoteCommand)
        var control = AuthenticatedDaemonControl()
        try control.arm(local, now: now)
        try control.complete(
            lockoutID: local.lockoutID,
            reason: .naturalExpiry,
            now: now.addingTimeInterval(31)
        )
        let status = control.status(
            external: remote,
            shutdownIssued: false,
            now: now.addingTimeInterval(31)
        )
        #expect(status.activeRecord?.lockoutID == remote.lockoutID)
    }

    @Test func transportCannotInventRemoteAuthority() {
        var control = AuthenticatedDaemonControl()
        #expect(throws: PrivilegedEnforcementError.invalidDeadline) {
            try control.arm(record(kind: .remoteCommand), now: now)
        }
    }

    @Test func heartbeatValidatesEffectiveIdentity() throws {
        var control = AuthenticatedDaemonControl()
        let remote = record(kind: .remoteCommand)
        #expect(throws: PrivilegedEnforcementError.lockoutMismatch) {
            try control.heartbeat(lockoutID: UUID(), external: remote, now: now)
        }
        try control.heartbeat(lockoutID: remote.lockoutID, external: remote, now: now)
        #expect(control.localStatus.lastHeartbeatAt == now)
    }

    @Test func wakeReleaseIsSpecificToItsLocalCampaign() throws {
        var control = AuthenticatedDaemonControl()
        let local = record()
        try control.arm(local, now: now)
        #expect(throws: PrivilegedEnforcementError.activeLockout) {
            try control.complete(lockoutID: local.lockoutID, reason: .accountWakeRelease, now: now)
        }
        var wakeControl = AuthenticatedDaemonControl()
        let wake = record(kind: .accountWakeCampaign)
        try wakeControl.arm(wake, now: now)
        try wakeControl.complete(lockoutID: wake.lockoutID, reason: .accountWakeRelease, now: now)
        #expect(wakeControl.localStatus.activeRecord == nil)
    }

    @Test func equalDateRemoteAuthorityCannotBecomeLocal() throws {
        var control = AuthenticatedDaemonControl()
        try control.arm(record(), now: now)
        let remote = record(kind: .remoteCommand)
        let effective = control.status(external: remote, shutdownIssued: false, now: now)
        #expect(effective.activeRecord?.kind == .remoteCommand)
        #expect(effective.activeRecord?.lockoutID == remote.lockoutID)
    }
}
