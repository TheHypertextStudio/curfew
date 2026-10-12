@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

final class NativeTransportURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var responseDelay: ((URLRequest) -> TimeInterval)?
    private let delivery = NativeTransportProtocolDelivery()

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                let path = request.url?.path ?? "missing URL"
                DispatchQueue.main.async { XCTFail("No transport handler for \(path)") }
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
            let delay = Self.responseDelay?(request) ?? 0
            delivery.schedule(after: delay, operation: deliver)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        delivery.cancel()
    }
}

/// Mirrors URLSession cancellation instead of delivering a response after teardown.
final class NativeTransportProtocolDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var pending: DispatchWorkItem?

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
