import Foundation

/// One daemon-managed source of lockout commands. Backends synchronize their
/// own transport and durable state, then expose only an authenticated active
/// deadline to the enforcement composition root.
public protocol DaemonCommandBackend {
    var name: String { get }

    func synchronize(at now: Date) throws -> [RemoteCommandDaemonReceipt]
    func activeDeadline(at now: Date) throws -> LockoutDeadlineRecord?
}

public struct DaemonCommandBackendFailure: Equatable, Sendable {
    public let backend: String
    public let message: String

    public init(backend: String, message: String) {
        self.backend = backend
        self.message = message
    }
}

public struct DaemonCommandBackendSnapshot: Equatable, Sendable {
    public let deadline: LockoutDeadlineRecord?
    public let receipts: [RemoteCommandDaemonReceipt]
    public let failures: [DaemonCommandBackendFailure]

    public init(
        deadline: LockoutDeadlineRecord?,
        receipts: [RemoteCommandDaemonReceipt],
        failures: [DaemonCommandBackendFailure]
    ) {
        self.deadline = deadline
        self.receipts = receipts
        self.failures = failures
    }
}

/// Daemon-owned dependency set. A transport or storage failure in one backend
/// cannot suppress a valid deadline supplied by another backend.
public struct DaemonCommandBackendSet {
    private let backends: [any DaemonCommandBackend]

    public init(backends: [any DaemonCommandBackend]) {
        self.backends = backends
    }

    public func synchronize(at now: Date) -> DaemonCommandBackendSnapshot {
        var deadline: LockoutDeadlineRecord?
        var receipts: [RemoteCommandDaemonReceipt] = []
        var failures: [DaemonCommandBackendFailure] = []

        for backend in backends {
            do {
                try receipts.append(contentsOf: backend.synchronize(at: now))
            } catch {
                failures.append(
                    DaemonCommandBackendFailure(
                        backend: backend.name,
                        message: error.localizedDescription
                    )
                )
            }

            do {
                let candidate = try backend.activeDeadline(at: now)
                deadline = DaemonLockoutDeadlineResolver.resolve(
                    now: now,
                    user: deadline,
                    shadow: nil,
                    remote: candidate
                )
            } catch {
                failures.append(
                    DaemonCommandBackendFailure(
                        backend: backend.name,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return DaemonCommandBackendSnapshot(
            deadline: deadline,
            receipts: receipts,
            failures: failures
        )
    }
}

/// Local MCP backend. The user-session server writes the user deadline; the
/// privileged daemon mirrors it into root-owned storage before enforcing it.
public struct DaemonLocalCommandBackend: DaemonCommandBackend {
    public let name = "local-mcp"

    private let userStore: LockoutDeadlineStore
    private let shadowStore: LockoutDeadlineStore

    public init(userStore: LockoutDeadlineStore, shadowStore: LockoutDeadlineStore) {
        self.userStore = userStore
        self.shadowStore = shadowStore
    }

    public func synchronize(at _: Date) throws -> [RemoteCommandDaemonReceipt] {
        if let record = userStore.load() {
            shadowStore.save(record)
        }
        return []
    }

    public func activeDeadline(at now: Date) throws -> LockoutDeadlineRecord? {
        DaemonLockoutDeadlineResolver.resolve(
            now: now,
            user: userStore.load(),
            shadow: shadowStore.load(),
            remote: nil
        )
    }
}

/// Remote MCP adapter around the authenticated command processor. The daemon
/// injects its storage and exchange boundary here instead of reaching for
/// remote-command globals from the enforcement loop.
public struct DaemonRemoteMCPBackend: DaemonCommandBackend {
    public let name = "remote-mcp"

    private let commandProcessor: DaemonRemoteCommandBackend
    private let stateStore: DaemonRemoteCommandStateStore
    private let resultExchange: RemoteCommandResultExchangeStore

    public init(
        commandProcessor: DaemonRemoteCommandBackend,
        stateStore: DaemonRemoteCommandStateStore,
        resultExchange: RemoteCommandResultExchangeStore
    ) {
        self.commandProcessor = commandProcessor
        self.stateStore = stateStore
        self.resultExchange = resultExchange
    }

    public func synchronize(at now: Date) throws -> [RemoteCommandDaemonReceipt] {
        try commandProcessor.reconcileResultExchange(resultExchange, at: now)
        let receipts = try commandProcessor.processPending(at: now)
        try commandProcessor.reconcileResultExchange(resultExchange, at: now)
        return receipts
    }

    public func activeDeadline(at now: Date) throws -> LockoutDeadlineRecord? {
        try DaemonLockoutDeadlineResolver.resolve(
            now: now,
            user: nil,
            shadow: nil,
            remote: stateStore.load().activeLockout
        )
    }
}
