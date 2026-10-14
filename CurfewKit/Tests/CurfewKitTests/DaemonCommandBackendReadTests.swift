import CurfewKit
import Foundation
import Testing

struct DaemonCommandBackendReadTests {
    @Test("Filtering a released local deadline preserves an active remote deadline")
    func releasedLocalDeadlinePreservesRemote() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let local = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-120),
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .accountWakeCampaign
        )
        let remote = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-30),
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .remoteCommand
        )
        let backends = DaemonCommandBackendSet(backends: [
            DeadlineBackend(name: "local", deadline: local),
            DeadlineBackend(name: "remote", deadline: remote)
        ])
        var control = AuthenticatedDaemonControl()
        try control.complete(
            lockoutID: local.lockoutID,
            reason: .accountWakeRelease,
            now: now,
            external: local
        )

        let snapshot = backends.activeDeadline(at: now) { candidate in
            control.activeLocalCandidate(candidate, now: now)
        }

        #expect(snapshot.deadline?.kind == .remoteCommand)
        #expect(snapshot.deadline?.scheduledUnlockAt == remote.scheduledUnlockAt)
        #expect(snapshot.receipts.isEmpty)
        #expect(snapshot.failures.isEmpty)
    }
}

private struct DeadlineBackend: DaemonCommandBackend {
    let name: String
    let deadline: LockoutDeadlineRecord

    func synchronize(at _: Date) throws -> [RemoteCommandDaemonReceipt] {
        throw DeadlineBackendError.unexpectedSynchronization
    }

    func activeDeadline(at _: Date) throws -> LockoutDeadlineRecord? {
        deadline
    }
}

private enum DeadlineBackendError: Error {
    case unexpectedSynchronization
}
