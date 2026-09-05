import Foundation

public enum RemoteCommandResultExchangeError: Error, Equatable {
    case resultIdentityMismatch
}

public struct RemoteCommandDaemonReceipt: Equatable, Sendable {
    public let cursor: String
    public let result: RemoteCommandResult

    public init(cursor: String, result: RemoteCommandResult) {
        self.cursor = cursor
        self.result = result
    }
}

/// Installed-daemon entry point for the remote backend. It resolves the
/// authenticated account/device binding before constructing the verifier, so
/// merely placing data in the user-writable inbox cannot activate remote
/// control on a Mac that has not completed enrollment.
public struct DaemonRemoteCommandBackend: Sendable {
    private let enrollmentStore: RemoteCommandEnrollmentStore
    private let inboxStore: RemoteCommandInboxStore
    private let stateStore: DaemonRemoteCommandStateStore
    private let jwksProvider: any RemoteCommandJWKSProvider

    public init(
        enrollmentStore: RemoteCommandEnrollmentStore,
        inboxStore: RemoteCommandInboxStore,
        stateStore: DaemonRemoteCommandStateStore,
        jwksProvider: any RemoteCommandJWKSProvider
    ) {
        self.enrollmentStore = enrollmentStore
        self.inboxStore = inboxStore
        self.stateStore = stateStore
        self.jwksProvider = jwksProvider
    }

    public func processPending(at now: Date = Date()) throws -> [RemoteCommandDaemonReceipt] {
        guard let enrollment = try enrollmentStore.load() else { return [] }
        let verifier = try RemoteCommandVerifier(
            configuration: RemoteCommandVerifierConfiguration(
                userID: enrollment.userID,
                deviceID: enrollment.deviceID
            ),
            jwksProvider: jwksProvider
        )
        return try DaemonRemoteCommandProcessor(
            inboxStore: inboxStore,
            verifier: verifier,
            controller: DaemonRemoteCommandController(store: stateStore)
        ).processPending(at: now)
    }

    public func reconcileResultExchange(
        _ exchange: RemoteCommandResultExchangeStore
    ) throws {
        let controller = DaemonRemoteCommandController(store: stateStore)
        for identity in try exchange.pendingAcknowledgements() {
            do {
                try controller.markReported(identity)
            } catch RemoteCommandResultExchangeError.resultIdentityMismatch {
                // Stale duplicates and forged user-side acknowledgements have
                // no authority over state and must not block valid results.
            }
            try exchange.removeAcknowledgement(identity)
        }
        try exchange.publish(stateStore.load().pendingResults)
    }
}

/// Daemon-owned composition root for the remote command backend. Delivery,
/// cryptographic verification, and the atomic enforcement transaction remain
/// separate dependencies so another platform can supply different storage or
/// process boundaries without changing command policy.
public struct DaemonRemoteCommandProcessor: Sendable {
    private let inboxStore: RemoteCommandInboxStore
    private let verifier: RemoteCommandVerifier
    private let controller: DaemonRemoteCommandController

    public init(
        inboxStore: RemoteCommandInboxStore,
        verifier: RemoteCommandVerifier,
        controller: DaemonRemoteCommandController
    ) {
        self.inboxStore = inboxStore
        self.verifier = verifier
        self.controller = controller
    }

    public func processPending(at now: Date = Date()) throws -> [RemoteCommandDaemonReceipt] {
        var receipts: [RemoteCommandDaemonReceipt] = []
        for delivery in try inboxStore.pendingDeliveries() {
            let envelope = try JSONEncoder().encode(delivery.envelope)
            let command: AuthenticatedRemoteCommand
            do {
                command = try verifier.verifiedLockoutRecord(envelope: envelope, at: now)
            } catch is RemoteCommandVerificationError {
                try inboxStore.remove(cursor: delivery.cursor)
                continue
            }
            let result = try controller.apply(command, at: now)
            try inboxStore.remove(cursor: delivery.cursor)
            receipts.append(RemoteCommandDaemonReceipt(cursor: delivery.cursor, result: result))
        }
        return receipts
    }
}

/// Serializes command application so replay state, the effective deadline, and
/// the result outbox are committed in one atomic state-file replacement.
public final class DaemonRemoteCommandController: @unchecked Sendable {
    private let store: DaemonRemoteCommandStateStore
    private let lock = NSLock()

    public init(store: DaemonRemoteCommandStateStore) {
        self.store = store
    }

    public func apply(
        _ command: AuthenticatedRemoteCommand,
        at now: Date = Date()
    ) throws -> RemoteCommandResult {
        lock.lock()
        defer { lock.unlock() }

        var state = try store.load()
        if let existing = state.resultsByIdempotencyKey[command.idempotencyKey] {
            return existing
        }

        let result: RemoteCommandResult
        if command.expiresAt <= now {
            result = RemoteCommandResult(
                commandID: command.lockoutID,
                deviceID: command.deviceID,
                sequence: command.sequence,
                stage: .expired,
                resolvedAt: now
            )
        } else if command.sequence <= state.highestSequence {
            result = RemoteCommandResult(
                commandID: command.lockoutID,
                deviceID: command.deviceID,
                sequence: command.sequence,
                stage: .rejected,
                resolvedAt: now,
                rejectionCode: .outOfOrder
            )
        } else {
            let current = state.activeLockout.flatMap { record in
                record.scheduledUnlockAt > now ? record : nil
            }
            let effectiveDeadline = max(
                current?.scheduledUnlockAt ?? command.scheduledUnlockAt,
                command.scheduledUnlockAt
            )
            state.activeLockout = LockoutDeadlineRecord(
                lockoutStartedAt: current?.lockoutStartedAt ?? now,
                scheduledUnlockAt: effectiveDeadline,
                kind: .remoteCommand
            )
            state.highestSequence = command.sequence
            result = RemoteCommandResult(
                commandID: command.lockoutID,
                deviceID: command.deviceID,
                sequence: command.sequence,
                stage: .applied,
                resolvedAt: now,
                appliedDeadline: effectiveDeadline
            )
        }

        state.resultsByIdempotencyKey[command.idempotencyKey] = result
        state.pendingResults.append(result)
        try store.save(state)
        return result
    }

    public func markReported(_ identity: RemoteCommandResultIdentity) throws {
        lock.lock()
        defer { lock.unlock() }

        var state = try store.load()
        guard state.pendingResults.contains(where: {
            $0.commandID == identity.commandID
                && $0.deviceID == identity.deviceID
                && $0.sequence == identity.sequence
        }) else {
            throw RemoteCommandResultExchangeError.resultIdentityMismatch
        }
        state.pendingResults.removeAll {
            $0.commandID == identity.commandID
                && $0.deviceID == identity.deviceID
                && $0.sequence == identity.sequence
        }
        try store.save(state)
    }
}
