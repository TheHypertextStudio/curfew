import CurfewKit
import Foundation

enum PrivilegedDaemonRPCError: LocalizedError, Equatable {
    case activeLockout
    case invalidResponse
    case stale
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .activeLockout:
            "The privileged helper cannot be removed while a lockout is active."
        case .invalidResponse:
            "The privileged helper returned an invalid response."
        case .stale:
            "The privileged helper heartbeat is stale. Relaunch Curfew before enforcement."
        case .unauthorized:
            "The privileged helper rejected this build's code signature."
        case .unavailable:
            "The privileged helper is unavailable. Install or approve it in System Settings."
        }
    }
}

protocol PrivilegedDaemonRPCControlling: Sendable {
    func armLockout(_ record: LockoutDeadlineRecord) async throws
    func heartbeat(lockoutID: UUID) async throws
    func completeLockout(lockoutID: UUID, reason: PrivilegedCompletionReason) async throws
    func status() async throws -> PrivilegedDaemonStatus
    func prepareForUninstall() async throws
}

enum DaemonRPCDeadline {
    static let productionTimeoutNanoseconds: UInt64 = 5_000_000_000

    static func run(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        operation: (@escaping (Result<Data, Error>) -> Void) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = DaemonRPCCompletionGate()
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard gate.claim() else { return }
                continuation.resume(throwing: PrivilegedDaemonRPCError.stale)
            }

            operation { result in
                guard gate.claim() else { return }
                timeoutTask.cancel()
                continuation.resume(with: result)
            }
        }
    }
}

private final class DaemonRPCCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

final class XPCPrivilegedDaemonClient: PrivilegedDaemonRPCControlling, @unchecked Sendable {
    func armLockout(_ record: LockoutDeadlineRecord) async throws {
        let request = try Self.encoder.encode(record)
        _ = try await call { proxy, reply in proxy.armLockout(request, reply: reply) }
    }

    func heartbeat(lockoutID: UUID) async throws {
        let request = try Self.encoder.encode(PrivilegedHeartbeatRequest(lockoutID: lockoutID))
        _ = try await call { proxy, reply in proxy.heartbeat(request, reply: reply) }
    }

    func completeLockout(lockoutID: UUID, reason: PrivilegedCompletionReason) async throws {
        let request = try Self.encoder.encode(PrivilegedHeartbeatRequest(lockoutID: lockoutID))
        _ = try await call { proxy, reply in
            proxy.completeLockout(request, reason: reason.rawValue, reply: reply)
        }
    }

    func status() async throws -> PrivilegedDaemonStatus {
        let response = try await call { proxy, reply in proxy.status(reply: reply) }
        return try Self.decoder.decode(PrivilegedDaemonStatus.self, from: response)
    }

    func prepareForUninstall() async throws {
        _ = try await call { proxy, reply in proxy.prepareForUninstall(reply: reply) }
    }

    private func call(
        _ operation: @escaping (
            CurfewDaemonXPCProtocol,
            @escaping (Data?, NSError?) -> Void
        ) -> Void
    ) async throws -> Data {
        let connection = NSXPCConnection(
            machServiceName: PrivilegedDaemonConstants.machServiceName,
            options: .privileged
        )
        defer { connection.invalidate() }
        connection.remoteObjectInterface = NSXPCInterface(with: CurfewDaemonXPCProtocol.self)

        return try await DaemonRPCDeadline.run { completion in
            let finish: (Data?, NSError?) -> Void = { data, error in
                if let error {
                    completion(.failure(Self.map(error)))
                } else if let data {
                    completion(.success(data))
                } else {
                    completion(.failure(PrivilegedDaemonRPCError.invalidResponse))
                }
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(nil, error as NSError)
            }) as? CurfewDaemonXPCProtocol else {
                completion(.failure(PrivilegedDaemonRPCError.unavailable))
                return
            }
            connection.resume()
            operation(proxy, finish)
        }
    }

    private static func map(_ error: NSError) -> PrivilegedDaemonRPCError {
        if error.domain == "studio.hypertext.curfew.daemon" {
            switch error.localizedDescription {
            case PrivilegedEnforcementError.activeLockout.rawValue:
                return .activeLockout
            case "unauthorized":
                return .unauthorized
            default:
                return .invalidResponse
            }
        }
        return .unavailable
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
