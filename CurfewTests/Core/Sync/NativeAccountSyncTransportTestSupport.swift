@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

/// A session owns its mock behavior, including requests Foundation constructs after invalidation.
/// Canceled sessions retain only a tombstone, never another test's handler or expectations.
final class NativeTransportProtocolSessions: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: NativeTransportProtocolSession] = [:]

    func bind(
        _ configuration: URLSessionConfiguration,
        handler: ((URLRequest) throws -> (Int, Data))?,
        delay: ((URLRequest) -> TimeInterval)?
    ) {
        let owner = UUID().uuidString
        let state = NativeTransportProtocolSession(handler: handler, delay: delay)
        lock.withLock { sessions[owner] = state }
        configuration.httpAdditionalHeaders = ["X-Curfew-Test-Session": owner]
    }

    func session(for request: URLRequest) -> NativeTransportProtocolSession? {
        guard let owner = request.value(forHTTPHeaderField: "X-Curfew-Test-Session") else {
            return nil
        }
        return lock.withLock { sessions[owner] }
    }

    func cancel(_ configuration: URLSessionConfiguration) {
        guard let owner = configuration.httpAdditionalHeaders?["X-Curfew-Test-Session"] as? String
        else { return }
        lock.withLock { sessions[owner] }?.cancel()
    }

    func replace(
        _ configuration: URLSessionConfiguration,
        handler: ((URLRequest) throws -> (Int, Data))?,
        delay: ((URLRequest) -> TimeInterval)?
    ) {
        guard let owner = configuration.httpAdditionalHeaders?["X-Curfew-Test-Session"] as? String
        else { return }
        lock.withLock { sessions[owner] }?.replace(handler: handler, delay: delay)
    }
}

final class NativeTransportProtocolSession: @unchecked Sendable {
    struct Response {
        let status: Int
        let data: Data
        let delay: TimeInterval
    }

    private let lock = NSLock()
    private var canceled = false
    private var handler: ((URLRequest) throws -> (Int, Data))?
    private var delay: ((URLRequest) -> TimeInterval)?

    init(
        handler: ((URLRequest) throws -> (Int, Data))?,
        delay: ((URLRequest) -> TimeInterval)?
    ) {
        self.handler = handler
        self.delay = delay
    }

    func response(to request: URLRequest) throws -> Response {
        let behavior = try lock.withLock {
            guard !canceled else { throw URLError(.cancelled) }
            guard let handler else {
                let path = request.url?.path ?? "unknown"
                DispatchQueue.main.async { XCTFail("No installed session handler for \(path)") }
                throw URLError(.badServerResponse)
            }
            return (handler, delay)
        }
        let (status, data) = try behavior.0(request)
        return Response(status: status, data: data, delay: behavior.1?(request) ?? 0)
    }

    func cancel() {
        lock.withLock {
            canceled = true
            handler = nil
            delay = nil
        }
    }

    func replace(
        handler: ((URLRequest) throws -> (Int, Data))?,
        delay: ((URLRequest) -> TimeInterval)?
    ) {
        lock.withLock {
            guard !canceled else { return }
            self.handler = handler
            self.delay = delay
        }
    }
}

final class NativeTransportURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var responseDelay: ((URLRequest) -> TimeInterval)?
    private let delivery = NativeTransportProtocolDelivery()
    private static let sessions = NativeTransportProtocolSessions()
    private let sessionState: NativeTransportProtocolSession?
    private let diagnosticID = UUID().uuidString

    override init(
        request: URLRequest,
        cachedResponse: CachedURLResponse?,
        client: (any URLProtocolClient)?
    ) {
        self.sessionState = Self.sessions.session(for: request)
        super.init(request: request, cachedResponse: cachedResponse, client: client)
        trace("constructed")
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    static func bind(_ configuration: URLSessionConfiguration) {
        sessions.bind(configuration, handler: handler, delay: responseDelay)
    }

    static func cancel(_ configuration: URLSessionConfiguration) {
        sessions.cancel(configuration)
    }

    static func replace(_ configuration: URLSessionConfiguration) {
        sessions.replace(configuration, handler: handler, delay: responseDelay)
    }

    override func startLoading() {
        trace("started")
        do {
            guard let sessionState else {
                let path = request.url?.path ?? "missing URL"
                let owner = request.value(forHTTPHeaderField: "X-Curfew-Test-Session") ?? "unknown"
                let diagnostic = "No transport handler for \(path); request=\(diagnosticID) " +
                    "session=\(owner) stopped=\(delivery.isStopped)"
                DispatchQueue.main.async { XCTFail(diagnostic) }
                throw URLError(.badServerResponse)
            }
            let result = try sessionState.response(to: request)
            let response = try XCTUnwrap(try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            let deliver = { [self] in
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: result.data)
                client?.urlProtocolDidFinishLoading(self)
            }
            delivery.schedule(after: result.delay, operation: deliver)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        trace("stopped")
        delivery.cancel()
    }

    private func trace(_ event: String) {
        let owner = request.value(forHTTPHeaderField: "X-Curfew-Test-Session") ?? "unknown"
        NSLog(
            "Curfew fixture %@ request=%@ session=%@ path=%@",
            event,
            diagnosticID,
            owner,
            request.url?.path ?? "unknown"
        )
    }
}

/// Mirrors URLSession cancellation instead of delivering a response after teardown.
final class NativeTransportProtocolDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var pending: DispatchWorkItem?

    var isStopped: Bool {
        lock.withLock { stopped }
    }

    func schedule(after delay: TimeInterval, operation: @escaping @Sendable () -> Void) {
        let work = DispatchWorkItem { [self] in
            let active = lock.withLock {
                pending = nil
                return !stopped
            }
            guard active else { return }
            operation()
        }
        let active = lock.withLock {
            guard !stopped else { return false }
            pending = work
            return true
        }
        guard active else { return }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work.perform()
        }
    }

    func cancel() {
        lock.withLock {
            stopped = true
            pending?.cancel()
            pending = nil
        }
    }
}

final class NativeTransportMemorySecretStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values.removeValue(forKey: account)
    }
}

final class NativeTransportEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

final class NativeTransportResponseDelayStore: @unchecked Sendable {
    private let lock = NSLock()
    private var delays: [String: TimeInterval] = [:]

    func set(_ delay: TimeInterval, for key: String) {
        lock.lock()
        delays[key] = delay
        lock.unlock()
    }

    func delay(for key: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return delays[key] ?? 0
    }
}
