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

/// Helper-local Sunrise operations stay separate from restriction enforcement.
protocol SunriseDaemonRPCControlling: Sendable {
    func replaceSunriseWakePlan(_ plan: SunriseWakePlan) async throws
    func cancelSunriseWakePlan() async throws
}

enum SunriseDaemonRPCError: Error, Equatable {
    case unavailable
    case rejected
    case invalidResponse
}

enum SunriseDaemonRPCMethod: Sendable, Equatable {
    case replace
    case cancel
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

final class XPCPrivilegedDaemonClient: PrivilegedDaemonRPCControlling, SunriseDaemonRPCControlling,
    @unchecked Sendable {
    typealias SunriseTransport = @Sendable (SunriseDaemonRPCMethod, Data?) async throws -> Data

    private let sunriseTransport: SunriseTransport?

    init(sunriseTransport: SunriseTransport? = nil) {
        self.sunriseTransport = sunriseTransport
    }

    func replaceSunriseWakePlan(_ plan: SunriseWakePlan) async throws {
        guard plan.owner.utf8.count <= 4096 else { throw SunriseDaemonRPCError.rejected }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let request = try? encoder.encode(plan), request.count <= 4096 else {
            throw SunriseDaemonRPCError.rejected
        }
        let response = try await performSunrise(.replace, request: request)
        guard response.count <= 4096 else { throw SunriseDaemonRPCError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // ISO transport drops fractional seconds; compare at the sent precision.
        guard let sent = try? decoder.decode(SunriseWakePlan.self, from: request),
              let echoed = try? decoder.decode(SunriseWakePlan.self, from: response),
              echoed == sent else { throw SunriseDaemonRPCError.invalidResponse }
    }

    func cancelSunriseWakePlan() async throws {
        let response = try await performSunrise(.cancel, request: nil)
        guard response.count <= 4096,
              (try? JSONDecoder().decode(Bool.self, from: response)) == true else {
            throw SunriseDaemonRPCError.invalidResponse
        }
    }

    private func performSunrise(
        _ method: SunriseDaemonRPCMethod,
        request: Data?
    ) async throws -> Data {
        if let sunriseTransport {
            return try await sunriseTransport(method, request)
        }
        do {
            switch method {
            case .replace:
                guard let request else { throw SunriseDaemonRPCError.rejected }
                return try await call(errorMap: Self.mapSunrise) { proxy, reply in
                    proxy.replaceSunriseWakePlan(request, reply: reply)
                }
            case .cancel:
                return try await call(errorMap: Self.mapSunrise) { proxy, reply in
                    proxy.cancelSunriseWakePlan(reply: reply)
                }
            }
        } catch let error as SunriseDaemonRPCError {
            throw error
        } catch let error as PrivilegedDaemonRPCError {
            switch error {
            case .stale, .unavailable: throw SunriseDaemonRPCError.unavailable
            case .invalidResponse: throw SunriseDaemonRPCError.invalidResponse
            case .activeLockout, .unauthorized: throw SunriseDaemonRPCError.rejected
            }
        } catch {
            throw SunriseDaemonRPCError.rejected
        }
    }

    private static func mapSunrise(_ error: NSError) -> Error {
        if error.domain == "studio.hypertext.curfew.daemon.sunrise", error.code == 1 {
            return SunriseDaemonRPCError.unavailable
        }
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case CocoaError.Code.xpcConnectionInterrupted.rawValue,
                 CocoaError.Code.xpcConnectionInvalid.rawValue:
                return SunriseDaemonRPCError.unavailable
            case CocoaError.Code.xpcConnectionReplyInvalid.rawValue:
                return SunriseDaemonRPCError.invalidResponse
            default: break
            }
        }
        return SunriseDaemonRPCError.rejected
    }

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
        errorMap: ((NSError) -> Error)? = nil,
        _ operation: @escaping (
            CurfewDaemonXPCProtocol,
            @escaping (Data?, NSError?) -> Void
        ) -> Void
    ) async throws -> Data {
        guard let identity = DaemonSigningIdentity.current else {
            throw PrivilegedDaemonRPCError.unauthorized
        }
        let connection = NSXPCConnection(
            machServiceName: identity.machServiceName,
            options: .privileged
        )
        defer { connection.invalidate() }
        connection.setCodeSigningRequirement(identity.serverRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: CurfewDaemonXPCProtocol.self)

        return try await DaemonRPCDeadline.run { completion in
            let finish: (Data?, NSError?) -> Void = { data, error in
                if let error {
                    completion(.failure(errorMap?(error) ?? Self.map(error)))
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
