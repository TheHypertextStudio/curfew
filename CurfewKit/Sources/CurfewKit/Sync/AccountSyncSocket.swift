import Foundation

/// Injectable network boundary. Only the app adapter owns the Foundation socket.
@MainActor
public protocol AccountSyncSocketConnection: AnyObject {
    var accessToken: String { get }
    var closeReason: String? { get }
    var failureStatusCode: Int? { get }
    func receive() async throws -> String
    func sendPing() async throws
    func close()
}

/// Owns the authenticated socket only. All state and command authority stays in HTTP.
@MainActor
public final class AccountSyncSocket {
    private let open: () async throws -> any AccountSyncSocketConnection
    private let onHint: () -> Void
    private let onFailure: (Error, String?, String?, Int?) async -> Bool
    private let clock = ContinuousClock()
    private let startedAt: ContinuousClock.Instant
    private let timeSource: (() -> Duration)?
    private var lifecycle =
        AccountSyncSocketLifecycle(retryJitter: .milliseconds(Int.random(in: 0 ... 5000)))
    private var connection: (any AccountSyncSocketConnection)?
    private var openingTask: Task<Void, Never>?
    private var receivingTask: Task<Void, Never>?
    private var sendingTask: Task<Void, Never>?
    private var generation = 0
    private var handlingFailure = false

    public init(
        open: @escaping () async throws -> any AccountSyncSocketConnection,
        onHint: @escaping () -> Void,
        onFailure: @escaping (Error, String?, String?, Int?) async -> Bool,
        elapsed: (() -> Duration)? = nil
    ) {
        self.open = open
        self.onHint = onHint
        self.onFailure = onFailure
        self.startedAt = clock.now
        self.timeSource = elapsed
    }

    public func tick() {
        guard !handlingFailure else { return }
        switch lifecycle.action(at: elapsed) {
        case .connect: connect()
        case .ping: ping()
        case .close:
            closeTasks()
        case nil: break
        }
    }

    public func stop() {
        lifecycle.failed(at: elapsed, terminal: true)
        closeTasks()
    }

    private var elapsed: Duration {
        timeSource?() ?? startedAt.duration(to: clock.now)
    }

    private func connect() {
        let current = generation
        let open = open
        openingTask = Task { [weak self] in
            do {
                let connection = try await open()
                guard let self, current == generation, !Task.isCancelled else {
                    connection.close()
                    return
                }
                self.connection = connection
                ping()
                receive(connection, generation: current)
            } catch {
                await self?.failed(error, generation: current)
            }
        }
    }

    private func receive(_ connection: any AccountSyncSocketConnection, generation current: Int) {
        receivingTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    guard let self, current == generation else { return }
                    if message == "pong" {
                        lifecycle.opened(at: elapsed)
                        lifecycle.receivedPong(at: elapsed)
                    } else {
                        onHint()
                    }
                }
            } catch {
                await self?.failed(error, generation: current)
            }
        }
    }

    private func ping() {
        guard let connection else { return }
        sendingTask?.cancel()
        let current = generation
        sendingTask = Task { [weak self] in
            do {
                try await connection.sendPing()
            } catch {
                await self?.failed(error, generation: current)
            }
        }
    }

    private func failed(_ error: Error, generation current: Int) async {
        guard current == generation, !handlingFailure, !Task.isCancelled else { return }
        handlingFailure = true
        let reason = connection?.closeReason
        let token = connection?.accessToken
        let status = connection?.failureStatusCode
        // Fence both the send and receive failure paths before awaiting token refresh.
        generation += 1
        let failureGeneration = generation
        let retry = await onFailure(error, reason, token, status)
        guard failureGeneration == generation else { return }
        closeTasks()
        lifecycle.failed(at: elapsed, terminal: !retry)
        handlingFailure = false
    }

    private func closeTasks() {
        generation += 1
        connection?.close()
        connection = nil
        openingTask?.cancel()
        receivingTask?.cancel()
        sendingTask?.cancel()
        openingTask = nil
        receivingTask = nil
        sendingTask = nil
    }
}
