@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct PrivilegedDaemonProtocolTests {
    @Test("daemon RPC deadline reports a stale unresponsive connection")
    func daemonRPCDeadlineTimesOut() async {
        await #expect(throws: PrivilegedDaemonRPCError.stale) {
            _ = try await DaemonRPCDeadline.run(timeoutNanoseconds: 1_000_000) { _ in }
        }
    }

    @Test("daemon RPC deadline returns the first response")
    func daemonRPCDeadlineReturnsResponse() async throws {
        let expected = Data("ok".utf8)

        let response = try await DaemonRPCDeadline
            .run(timeoutNanoseconds: 1_000_000_000) { completion in
                completion(.success(expected))
            }

        #expect(response == expected)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Legacy lockout records decode with a migrated lockout identifier")
    func legacyDeadlineMigration() throws {
        let data = Data(
            """
            {
              "kind": "scheduled_time",
              "lockoutStartedAt": "2027-01-15T08:00:00Z",
              "scheduledUnlockAt": "2027-01-15T16:00:00Z"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = try decoder.decode(LockoutDeadlineRecord.self, from: data)

        #expect(record.lockoutID != UUID.zero)
    }

    @Test("Loading a legacy deadline persists its migrated identifier")
    func legacyDeadlineStorePersistsMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("lockout.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(
            """
            {
              "kind": "scheduled_time",
              "lockoutStartedAt": "2027-01-15T08:00:00Z",
              "scheduledUnlockAt": "2027-01-15T16:00:00Z"
            }
            """.utf8
        ).write(to: url)

        let store = LockoutDeadlineStore(recordURL: url)
        let migrated = try #require(store.load())
        let persistedData = try Data(contentsOf: url)
        let persisted = try JSONDecoder.curfewISO8601.decode(
            LockoutDeadlineRecord.self,
            from: persistedData
        )

        #expect(persisted.lockoutID == migrated.lockoutID)
    }

    @Test("Daemon state storage is restart-safe and root-permission compatible")
    func daemonStateStorageContract() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = parent.appendingPathComponent("lockout-state.json")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PrivilegedDaemonStateStore(stateURL: url)
        let expected = PrivilegedDaemonStatus(
            activeRecord: makeRecord(),
            lastHeartbeatAt: now,
            shutdownIssued: true
        )

        try store.save(expected)

        #expect(try store.load() == expected)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: parent.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(directoryAttributes[.posixPermissions] as? NSNumber == 0o755)
        #expect(fileAttributes[.posixPermissions] as? NSNumber == 0o600)

        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: parent.path))
    }

    @Test("Daemon protocol payloads preserve the lockout identifier")
    func protocolPayloadRoundTrip() throws {
        let record = makeRecord()
        let payload = PrivilegedDaemonStatus(
            activeRecord: record,
            lastHeartbeatAt: now,
            shutdownIssued: false
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PrivilegedDaemonStatus.self, from: data)

        #expect(decoded == payload)
    }

    @Test("Daemon rejects deadlines that have already elapsed")
    func armRejectsExpiredDeadline() {
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        let expired = LockoutDeadlineRecord(
            lockoutID: UUID(),
            lockoutStartedAt: now.addingTimeInterval(-120),
            scheduledUnlockAt: now.addingTimeInterval(-1),
            kind: .scheduledTime
        )

        #expect(throws: PrivilegedEnforcementError.invalidDeadline) {
            try machine.arm(expired, now: now)
        }
    }

    @Test("Matching heartbeats keep an armed lockout alive")
    func heartbeatKeepsLockoutAlive() throws {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        try machine.arm(record, now: now)

        try machine.heartbeat(lockoutID: record.lockoutID, now: now.addingTimeInterval(80))

        #expect(
            machine.evaluate(
                now: now.addingTimeInterval(160),
                heartbeatTimeout: 90
            ) == .none
        )
    }

    @Test("A stale heartbeat requests shutdown exactly once")
    func staleHeartbeatRequestsOneShutdown() throws {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        try machine.arm(record, now: now)

        #expect(
            machine.evaluate(now: now.addingTimeInterval(91), heartbeatTimeout: 90)
                == .shutdown
        )
        #expect(
            machine.evaluate(now: now.addingTimeInterval(120), heartbeatTimeout: 90)
                == .none
        )
    }

    @Test("Restarted daemon retains the active record and grants a startup heartbeat grace")
    func restartRecovery() {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(record: record, startedAt: now)

        #expect(machine.status.activeRecord == record)
        #expect(machine.evaluate(now: now.addingTimeInterval(89), heartbeatTimeout: 90) == .none)
        #expect(machine
            .evaluate(now: now.addingTimeInterval(91), heartbeatTimeout: 90) == .shutdown)
    }

    @Test("Natural completion is rejected before the authoritative deadline")
    func naturalCompletionCannotBypassDeadline() throws {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        try machine.arm(record, now: now)

        #expect(throws: PrivilegedEnforcementError.activeLockout) {
            try machine.complete(
                lockoutID: record.lockoutID,
                reason: .naturalExpiry,
                now: now.addingTimeInterval(60)
            )
        }
        #expect(machine.status.activeRecord == record)
    }

    @Test("An approved override completes the matching lockout")
    func approvedOverrideCompletesLockout() throws {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        try machine.arm(record, now: now)

        try machine.complete(
            lockoutID: record.lockoutID,
            reason: .approvedOverride,
            now: now.addingTimeInterval(60)
        )

        #expect(machine.status.activeRecord == nil)
    }

    @Test("Uninstall is rejected while a lockout remains active")
    func uninstallRejectedDuringLockout() throws {
        let record = makeRecord()
        var machine = PrivilegedEnforcementStateMachine(startedAt: now)
        try machine.arm(record, now: now)

        #expect(throws: PrivilegedEnforcementError.activeLockout) {
            try machine.prepareForUninstall(now: now.addingTimeInterval(60))
        }
    }

    @Test("Client identity policy requires both the release team and bundle")
    func clientIdentityPolicy() {
        let policy = DaemonClientIdentityPolicy(
            expectedTeamIdentifier: "39AB9DY3K8",
            expectedBundleIdentifier: "studio.hypertext.curfew"
        )

        #expect(policy.accepts(
            teamIdentifier: "39AB9DY3K8",
            bundleIdentifier: "studio.hypertext.curfew"
        ))
        #expect(!policy.accepts(
            teamIdentifier: "ATTACKER00",
            bundleIdentifier: "studio.hypertext.curfew"
        ))
        #expect(!policy.accepts(
            teamIdentifier: "39AB9DY3K8",
            bundleIdentifier: "studio.hypertext.curfew.dev"
        ))
    }

    @Test("Daemon signing requirement pins the release team and app bundle")
    func daemonSigningRequirement() {
        let expected = "anchor apple generic and "
            + "certificate leaf[subject.OU] = \"39AB9DY3K8\" and "
            + "identifier \"studio.hypertext.curfew\""

        #expect(PrivilegedDaemonConstants.clientSigningRequirement == expected)
    }

    private func makeRecord() -> LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutID: UUID(),
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .scheduledTime
        )
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

private extension JSONDecoder {
    static var curfewISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
