@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncOverrideCadenceTests: XCTestCase {
    func testOldSocketRefreshRejectionCannotStopAReplacementConnection() async throws {
        let fixture = try makeFixture(
            accessToken: "expired-access-token", refreshToken: "old-refresh",
            clientID: "native-client"
        )
        let refreshStarted = expectation(description: "old socket refresh started")
        installDelayedRejectedRefreshHandler(refreshStarted: refreshStarted)
        defer {
            NativeOverrideCadenceURLProtocol.handler = nil
            NativeOverrideCadenceURLProtocol.responseDelay = nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeOverrideCadenceURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Curfew-Test-Session": UUID().uuidString]
        let lifetime = NativeCadenceSessionLifetime()
        let session = URLSession(
            configuration: configuration,
            delegate: lifetime,
            delegateQueue: nil
        )
        let transport = NativeAccountSyncTransport(
            secretStore: fixture.secrets, session: session,
            socketEnabled: false
        )
        let previousGeneration = transport.connectionGeneration
        let oldFailure = Task {
            await transport.handleSocketFailure(
                NativeAccountSyncError.rejected(401), reason: nil,
                token: "expired-access-token", generation: previousGeneration
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 1)
        try fixture.secrets.save(Data("fresh-access-token".utf8), for: "oauth-access-token")
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in }, onOffline: {}, onWakeStatus: { _ in },
                onRemoteOverride: { _ in }, onRemoteCommandResult: { _ in }, onFailure: { _ in }
            )
        )
        let replacementGeneration = transport.connectionGeneration
        _ = await oldFailure.value
        XCTAssertEqual(transport.connectionGeneration, replacementGeneration)
        await transport.disconnectAndWaitForPendingOperations()
        await lifetime.invalidate(session)
    }

    func testOverridePollingContinuesWhileWakeStatusHangs() async throws {
        let fixture = try makeFixture()
        let polledTwice = expectation(description: "override cadence remained independent")
        polledTwice.expectedFulfillmentCount = 2
        polledTwice.assertForOverFulfill = false
        installHandler(polledTwice: polledTwice)
        defer {
            NativeOverrideCadenceURLProtocol.handler = nil
            NativeOverrideCadenceURLProtocol.responseDelay = nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeOverrideCadenceURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Curfew-Test-Session": UUID().uuidString]
        let lifetime = NativeCadenceSessionLifetime()
        let session = URLSession(
            configuration: configuration,
            delegate: lifetime,
            delegateQueue: nil
        )
        let transport = NativeAccountSyncTransport(
            secretStore: fixture.secrets,
            session: session,
            pollingInterval: .milliseconds(20),
            socketEnabled: false
        )

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in },
                onOffline: {},
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )

        await fulfillment(of: [polledTwice], timeout: 0.15)
        await transport.disconnectAndWaitForPendingOperations()
        await lifetime.invalidate(session)
    }

    func testStaggeredStaleTokenResponsesShareOneRefreshGeneration() async throws {
        let fixture = try makeFixture(
            accessToken: "expired-access-token",
            refreshToken: "rotating-refresh-token",
            clientID: "curfew-native-client"
        )
        let refreshes = NativeTransportEventRecorder()
        let staleChallengeDelays = NativeTransportDelaySequencer()
        installStaggeredRefreshHandler(
            refreshes: refreshes,
            delays: staleChallengeDelays
        )
        defer {
            NativeOverrideCadenceURLProtocol.handler = nil
            NativeOverrideCadenceURLProtocol.responseDelay = nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeOverrideCadenceURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Curfew-Test-Session": UUID().uuidString]
        let lifetime = NativeCadenceSessionLifetime()
        let session = URLSession(
            configuration: configuration,
            delegate: lifetime,
            delegateQueue: nil
        )
        let transport = NativeAccountSyncTransport(
            secretStore: fixture.secrets,
            session: session,
            pollingInterval: .seconds(10),
            socketEnabled: false
        )

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in },
                onOffline: {},
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )
        try await Task.sleep(for: .milliseconds(250))
        await transport.disconnectAndWaitForPendingOperations()
        await lifetime.invalidate(session)

        XCTAssertEqual(refreshes.values, ["refresh"])
    }

    private func installDelayedRejectedRefreshHandler(refreshStarted: XCTestExpectation) {
        NativeOverrideCadenceURLProtocol.responseDelay = {
            $0.url?.path == "/api/auth/oauth2/token" ? 0.1 : 0
        }
        NativeOverrideCadenceURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/oauth2/token" {
                refreshStarted.fulfill()
                return (400, Data())
            }
            switch request.url?.path {
            case "/sync/device-proof/challenge":
                return (
                    200,
                    Data(#"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","keyEpoch":1}"#.utf8)
                )
            case "/sync/devices": return (200, Data("[]".utf8))
            case "/sync/wake/status", "/sync/remote-overrides/active": return (404, Data())
            case "/sync/remote-control/commands":
                return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
            default: throw NativeAccountSyncError.invalidResponse
            }
        }
    }

    private func makeFixture(
        accessToken: String = "resource-bound-access-token",
        refreshToken: String? = nil,
        clientID: String? = nil
    ) throws -> (
        deviceID: UUID,
        secrets: NativeTransportMemorySecretStore
    ) {
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let secrets = NativeTransportMemorySecretStore()
        try secrets.save(Data(accessToken.utf8), for: "oauth-access-token")
        if let refreshToken {
            try secrets.save(Data(refreshToken.utf8), for: "oauth-refresh-token")
        }
        if let clientID {
            try secrets.save(Data(clientID.utf8), for: "oauth-client-id")
        }
        _ = try AccountDeviceKeyStore(secretStore: secrets).createEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return (deviceID, secrets)
    }

    private func installHandler(polledTwice: XCTestExpectation) {
        NativeOverrideCadenceURLProtocol.responseDelay = { request in
            request.url?.path == "/sync/wake/status" ? 0.25 : 0
        }
        NativeOverrideCadenceURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                let body = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
                    #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
                return (200, Data(body.utf8))
            case ("GET", "/sync/devices"):
                return (200, Data("[]".utf8))
            case ("GET", "/sync/remote-overrides/active"):
                polledTwice.fulfill()
                return (404, Data())
            case ("GET", "/sync/wake/status"):
                return (500, Data())
            case ("GET", "/sync/remote-control/commands"):
                return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    private func installStaggeredRefreshHandler(
        refreshes: NativeTransportEventRecorder,
        delays: NativeTransportDelaySequencer
    ) {
        NativeOverrideCadenceURLProtocol.responseDelay = { request in
            guard request.url?.path == "/sync/device-proof/challenge",
                  request.value(forHTTPHeaderField: "Authorization") ==
                  "Bearer expired-access-token"
            else { return 0 }
            return delays.nextDelay()
        }
        NativeOverrideCadenceURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if path == "/api/auth/oauth2/token" {
                refreshes.append("refresh")
                let json = #"{"access_token":"fresh-access-token","# +
                    #""refresh_token":"fresh-refresh-token","token_type":"Bearer"}"#
                return (200, Data(json.utf8))
            }
            if authorization == "Bearer expired-access-token" {
                return (401, Data())
            }
            XCTAssertEqual(authorization, "Bearer fresh-access-token")
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                let body = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
                    #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
                return (200, Data(body.utf8))
            case ("GET", "/sync/devices"):
                return (200, Data("[]".utf8))
            case ("GET", "/sync/wake/status"),
                 ("GET", "/sync/remote-overrides/active"):
                return (404, Data())
            case ("GET", "/sync/remote-control/commands"):
                return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }
}

private final class NativeCadenceSessionLifetime: NSObject, URLSessionDelegate,
    @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    func invalidate(_ session: URLSession) async {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError _: Error?) {
        let owner = session.configuration.httpAdditionalHeaders?["X-Curfew-Test-Session"]
            as? String ?? "unknown"
        NSLog("Curfew cadence fixture session invalidated session=%@", owner)
        let completion = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        completion?.resume()
    }
}

private final class NativeTransportDelaySequencer: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func nextDelay() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count == 1 ? 0 : 0.1
    }
}

private final class NativeOverrideCadenceURLProtocol: URLProtocol, @unchecked Sendable {
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
                let diagnostic = "No cadence handler for \(path); request=\(diagnosticID) " +
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
            "Curfew cadence fixture %@ request=%@ session=%@ path=%@",
            event,
            diagnosticID,
            owner,
            request.url?.path ?? "unknown"
        )
    }
}
