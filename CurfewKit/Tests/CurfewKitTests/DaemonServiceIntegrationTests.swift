import CurfewKit
import Foundation
import Testing

struct DaemonServiceIntegrationTests {
    @Test func corruptLocalStateDoesNotSuppressIndependentAuthority() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        let damaged = Data("not-json".utf8)
        try damaged.write(to: url)
        let now = Date()
        let remote = LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .remoteCommand
        )
        let service = AuthenticatedDaemonService(
            store: PrivilegedDaemonStateStore(stateURL: url),
            readExternal: { _, _ in remote },
            evaluate: { _, _, _ in false },
            discover: {}
        )
        let policyState = await service.evaluateNow()
        #expect(policyState.activeRecord?.lockoutID == remote.lockoutID)
        let (_, error) = await status(service)
        #expect(error != nil)
        #expect(try Data(contentsOf: url) == damaged)
    }

    @Test func failedPersistenceNeverAcknowledgesOrAppliesAnArm() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory)
        let service = AuthenticatedDaemonService(
            store: PrivilegedDaemonStateStore(stateURL: directory
                .appendingPathComponent("state.json")),
            readExternal: { _, _ in nil },
            evaluate: { _, _, _ in false },
            discover: {}
        )
        let now = Date()
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .scheduledTime
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let request = try encoder.encode(record)
        let result: (Data?, NSError?) = await withCheckedContinuation { continuation in
            service.armLockout(request) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(result.0 == nil)
        #expect(result.1 != nil)
        let state = await service.evaluateNow()
        #expect(state.activeRecord == nil)
    }

    private func status(_ service: AuthenticatedDaemonService) async -> (Data?, NSError?) {
        await withCheckedContinuation { continuation in
            service.status { continuation.resume(returning: ($0, $1)) }
        }
    }
}
