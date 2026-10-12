@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

final class NativeTransportURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var responseDelay: ((URLRequest) -> TimeInterval)?
    private let delivery = NativeTransportProtocolDelivery()
    private let requestHandler: ((URLRequest) throws -> (Int, Data))?
    private let requestDelay: ((URLRequest) -> TimeInterval)?
    private let diagnosticID = UUID().uuidString

    override init(
        request: URLRequest,
        cachedResponse: CachedURLResponse?,
        client: (any URLProtocolClient)?
    ) {
        self.requestHandler = Self.handler
        self.requestDelay = Self.responseDelay
        super.init(request: request, cachedResponse: cachedResponse, client: client)
        trace("constructed")
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        trace("started")
        do {
            guard let handler = requestHandler else {
                let path = request.url?.path ?? "missing URL"
                let owner = request.value(forHTTPHeaderField: "X-Curfew-Test-Session") ?? "unknown"
                let diagnostic = "No transport handler for \(path); request=\(diagnosticID) " +
                    "session=\(owner) stopped=\(delivery.isStopped)"
                DispatchQueue.main.async { XCTFail(diagnostic) }
                throw URLError(.badServerResponse)
            }
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(try HTTPURLResponse(
                url: XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            let deliver = { [self] in
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            let delay = requestDelay?(request) ?? 0
            delivery.schedule(after: delay, operation: deliver)
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
