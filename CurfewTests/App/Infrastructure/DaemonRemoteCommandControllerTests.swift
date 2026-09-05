@testable import Curfew
import Foundation
import Testing

struct DaemonRemoteCommandControllerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let deviceID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!

    @Test("A remote command durably commits its lockout and result together")
    func commitsLockoutAndResult() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        let command = makeCommand(sequence: 1, duration: 3600)

        let result = try controller.apply(command, at: now)
        let persisted = try store.load()

        #expect(result.stage == .applied)
        #expect(result.appliedDeadline == now.addingTimeInterval(3600))
        #expect(persisted.highestSequence == 1)
        #expect(persisted.activeLockout?.kind == .remoteCommand)
        #expect(persisted.activeLockout?.scheduledUnlockAt == now.addingTimeInterval(3600))
        #expect(persisted.pendingResults == [result])
    }

    @Test("Retrying one command returns its durable result without duplicating the outbox")
    func idempotentRetryUsesDurableResult() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        let command = makeCommand(sequence: 1, duration: 900)

        let first = try controller.apply(command, at: now)
        let retry = try controller.apply(command, at: now.addingTimeInterval(30))
        let persisted = try store.load()

        #expect(retry == first)
        #expect(persisted.pendingResults == [first])
    }

    @Test("A newer remote command can strengthen but never shorten an active lockout")
    func lockoutsOnlyStrengthen() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        _ = try controller.apply(makeCommand(sequence: 1, duration: 3600), at: now)

        let shorter = try controller.apply(
            makeCommand(sequence: 2, duration: 300),
            at: now.addingTimeInterval(30)
        )
        let persisted = try store.load()

        #expect(shorter.stage == .applied)
        #expect(shorter.appliedDeadline == now.addingTimeInterval(3600))
        #expect(persisted.activeLockout?.scheduledUnlockAt == now.addingTimeInterval(3600))
    }

    @Test("An out-of-order signed command is rejected without changing the active deadline")
    func rejectsOutOfOrderCommand() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        _ = try controller.apply(makeCommand(sequence: 2, duration: 900), at: now)

        let replay = try controller.apply(
            makeCommand(sequence: 1, duration: 3600),
            at: now.addingTimeInterval(10)
        )
        let persisted = try store.load()

        #expect(replay.stage == .rejected)
        #expect(replay.rejectionCode == .outOfOrder)
        #expect(persisted.highestSequence == 2)
        #expect(persisted.activeLockout?.scheduledUnlockAt == now.addingTimeInterval(900))
        #expect(persisted.pendingResults.last == replay)
    }

    @Test("Acknowledging a reported result removes only that result from the durable outbox")
    func acknowledgesReportedResult() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        let first = try controller.apply(makeCommand(sequence: 1, duration: 300), at: now)
        let second = try controller.apply(makeCommand(sequence: 2, duration: 600), at: now)

        try controller.markReported(RemoteCommandResultIdentity(result: first))
        let persisted = try store.load()

        #expect(persisted.pendingResults == [second])
        #expect(persisted.resultsByIdempotencyKey.count == 2)
    }

    @Test("A mismatched publication acknowledgement cannot remove a daemon result")
    func rejectsMismatchedResultAcknowledgement() throws {
        let store = try makeStore()
        let controller = DaemonRemoteCommandController(store: store)
        let result = try controller.apply(makeCommand(sequence: 1, duration: 300), at: now)
        let wrong = RemoteCommandResultIdentity(
            commandID: result.commandID,
            deviceID: result.deviceID,
            sequence: result.sequence + 1
        )

        #expect(throws: RemoteCommandResultExchangeError.resultIdentityMismatch) {
            try controller.markReported(wrong)
        }
        #expect(try store.load().pendingResults == [result])
    }

    @Test("Daemon command backend stays inert until this Mac has an authenticated enrollment")
    func backendRequiresEnrollment() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = DaemonRemoteCommandBackend(
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("missing-enrollment.json")
            ),
            inboxStore: RemoteCommandInboxStore(
                directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
            ),
            stateStore: DaemonRemoteCommandStateStore(
                stateURL: root.appendingPathComponent("state.json")
            ),
            jwksProvider: UnavailableRemoteCommandJWKSProvider()
        )

        #expect(try backend.processPending(at: now).isEmpty)
        #expect(!FileManager.default
            .fileExists(atPath: root.appendingPathComponent("state.json").path))
    }

    @Test("Daemon republishes results until the app confirms coordinator acceptance")
    func backendReconcilesResultExchange() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = DaemonRemoteCommandStateStore(
            stateURL: root.appendingPathComponent("state.json")
        )
        let result = try DaemonRemoteCommandController(store: state)
            .apply(makeCommand(sequence: 1, duration: 300), at: now)
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        let backend = DaemonRemoteCommandBackend(
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("enrollment.json")
            ),
            inboxStore: RemoteCommandInboxStore(
                directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
            ),
            stateStore: state,
            jwksProvider: UnavailableRemoteCommandJWKSProvider()
        )

        try backend.reconcileResultExchange(exchange)
        #expect(try exchange.pendingResults() == [result])

        try exchange.acknowledge(RemoteCommandResultIdentity(result: result))
        try backend.reconcileResultExchange(exchange)
        #expect(try state.load().pendingResults.isEmpty)
        #expect(try exchange.pendingResults().isEmpty)
        #expect(try exchange.pendingAcknowledgements().isEmpty)
    }

    private func makeStore() throws -> DaemonRemoteCommandStateStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DaemonRemoteCommandStateStore(
            stateURL: directory.appendingPathComponent("remote-command-state.json")
        )
    }

    private func makeCommand(sequence: Int64, duration: Int) -> AuthenticatedRemoteCommand {
        AuthenticatedRemoteCommand(
            lockoutID: UUID(),
            idempotencyKey: "key_\(sequence)_abcdefghijklmnopq",
            userID: "remote-command-user",
            deviceID: deviceID,
            sequence: sequence,
            scheduledUnlockAt: now.addingTimeInterval(TimeInterval(duration)),
            issuedAt: now.addingTimeInterval(-30),
            expiresAt: now.addingTimeInterval(60),
            nonce: "nonce_abcdefghijklmnopq",
            statusVersion: 4,
            scheduleDigest: String(repeating: "S", count: 43)
        )
    }
}

private struct UnavailableRemoteCommandJWKSProvider: RemoteCommandJWKSProvider {
    func jwks() throws -> RemoteCommandJWKS {
        Issue.record("An unenrolled daemon must not fetch coordinator keys")
        return RemoteCommandJWKS(keys: [])
    }
}
