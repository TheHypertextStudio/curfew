@testable import Curfew
import Foundation
import Testing

struct DaemonCommandBackendTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Local MCP deadlines are shadowed through the daemon backend boundary")
    func localBackendShadowsDeadline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let user = LockoutDeadlineStore(recordURL: root.appendingPathComponent("user.json"))
        let shadow = LockoutDeadlineStore(recordURL: root.appendingPathComponent("shadow.json"))
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-60),
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .scheduledTime
        )
        user.save(record)
        let backend = DaemonLocalCommandBackend(userStore: user, shadowStore: shadow)

        #expect(throws: Never.self) { try backend.synchronize(at: now) }
        #expect(try backend.activeDeadline(at: now) == record)
        #expect(shadow.load() == record)

        user.clear()
        #expect(try backend.activeDeadline(at: now) == record)
    }

    @Test("Backend failures are isolated while the strongest deadline still wins")
    func backendSetIsolatesFailures() {
        let local = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-120),
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .scheduledTime
        )
        let remote = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-30),
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .remoteCommand
        )
        let set = DaemonCommandBackendSet(backends: [
            StubDaemonCommandBackend(name: "local", deadline: local),
            StubDaemonCommandBackend(name: "broken", deadlineFailure: TestBackendError.failed),
            StubDaemonCommandBackend(name: "remote", deadline: remote)
        ])

        let snapshot = set.synchronize(at: now)

        #expect(snapshot.deadline?.scheduledUnlockAt == remote.scheduledUnlockAt)
        #expect(snapshot.deadline?.lockoutStartedAt == local.lockoutStartedAt)
        #expect(snapshot.failures.map(\.backend) == ["broken"])
    }

    @Test("A synchronization failure cannot suppress that backend's durable deadline")
    func synchronizationFailurePreservesDurableDeadline() {
        let remote = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-30),
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .remoteCommand
        )
        let set = DaemonCommandBackendSet(backends: [
            StubDaemonCommandBackend(
                name: "remote",
                deadline: remote,
                synchronizationFailure: TestBackendError.failed
            )
        ])

        let snapshot = set.synchronize(at: now)

        #expect(snapshot.deadline?.scheduledUnlockAt == remote.scheduledUnlockAt)
        #expect(snapshot.failures.map(\.backend) == ["remote"])
    }

    @Test("Remote MCP backend reconciles results and supplies its active deadline")
    func remoteBackendOwnsTransportAndDeadline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let deadline = LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-30),
            scheduledUnlockAt: now.addingTimeInterval(1800),
            kind: .remoteCommand
        )
        let result = RemoteCommandResult(
            commandID: UUID(),
            deviceID: UUID(),
            sequence: 1,
            stage: .applied,
            resolvedAt: now,
            appliedDeadline: deadline.scheduledUnlockAt
        )
        let stateStore = DaemonRemoteCommandStateStore(
            stateURL: root.appendingPathComponent("state.json")
        )
        try stateStore.save(
            DaemonRemoteCommandState(
                highestSequence: 1,
                activeLockout: deadline,
                pendingResults: [result]
            )
        )
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("acks", isDirectory: true)
        )
        let commandProcessor = DaemonRemoteCommandBackend(
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("missing-enrollment.json")
            ),
            inboxStore: RemoteCommandInboxStore(
                directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
            ),
            stateStore: stateStore,
            jwksProvider: BackendUnavailableJWKSProvider()
        )
        let backend = DaemonRemoteMCPBackend(
            commandProcessor: commandProcessor,
            stateStore: stateStore,
            resultExchange: exchange
        )

        #expect(try backend.synchronize(at: now).isEmpty)
        #expect(try backend.activeDeadline(at: now) == deadline)
        #expect(try exchange.pendingResults() == [result])
    }
}

private enum TestBackendError: Error {
    case failed
}

private struct StubDaemonCommandBackend: DaemonCommandBackend {
    let name: String
    var deadline: LockoutDeadlineRecord?
    var synchronizationFailure: Error?
    var deadlineFailure: Error?

    init(
        name: String,
        deadline: LockoutDeadlineRecord? = nil,
        synchronizationFailure: Error? = nil,
        deadlineFailure: Error? = nil
    ) {
        self.name = name
        self.deadline = deadline
        self.synchronizationFailure = synchronizationFailure
        self.deadlineFailure = deadlineFailure
    }

    func synchronize(at _: Date) throws -> [RemoteCommandDaemonReceipt] {
        if let synchronizationFailure {
            throw synchronizationFailure
        }
        return []
    }

    func activeDeadline(at _: Date) throws -> LockoutDeadlineRecord? {
        if let deadlineFailure {
            throw deadlineFailure
        }
        return deadline
    }
}

private struct BackendUnavailableJWKSProvider: RemoteCommandJWKSProvider {
    func jwks() throws -> RemoteCommandJWKS {
        throw TestBackendError.failed
    }
}
