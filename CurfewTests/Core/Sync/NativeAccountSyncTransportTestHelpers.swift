@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func makeFixture(
        accessToken: String,
        refreshToken: String? = nil,
        clientID: String? = nil
    ) throws -> (deviceID: UUID, secrets: NativeTransportMemorySecretStore) {
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

    func makeTransport(
        secrets: NativeTransportMemorySecretStore,
        inboxStore: RemoteCommandInboxStore? = nil,
        resultExchangeStore: RemoteCommandResultExchangeStore? = nil,
        enrollmentStore: RemoteCommandEnrollmentStore? = nil,
        pollingInterval: Duration = .seconds(15),
        now: @escaping () -> Date = Date.init
    ) -> NativeAccountSyncTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeTransportURLProtocol.self]
        return NativeAccountSyncTransport(
            secretStore: secrets,
            session: URLSession(configuration: configuration),
            inboxStore: inboxStore,
            resultExchangeStore: resultExchangeStore,
            enrollmentStore: enrollmentStore,
            pollingInterval: pollingInterval,
            now: now
        )
    }

    func installPollingHandler(
        batch: RemoteCommandDeliveryBatch,
        onCommands: (() -> Void)? = nil
    ) {
        NativeTransportURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                return Self.challengeResponse()
            case ("GET", "/sync/devices"):
                return (200, Data("[]".utf8))
            case ("GET", "/sync/wake/status"),
                 ("GET", "/sync/remote-overrides/active"):
                return (404, Data())
            case ("GET", "/sync/remote-control/commands"):
                onCommands?()
                return try (200, batch.jsonData())
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
    }

    func installRefreshHandler(events: NativeTransportEventRecorder) {
        NativeTransportURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            if path == "/api/auth/oauth2/token" {
                events.append("refresh")
                return Self.freshTokensResponse(for: request)
            }
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if authorization == "Bearer expired-access-token" {
                events.append("expired")
                return (401, Data())
            }
            XCTAssertEqual(authorization, "Bearer fresh-access-token")
            if path == "/sync/remote-control/commands" {
                events.append("commands")
            }
            return try Self.pollingResponse(for: request)
        }
    }

    func installResultHandler(events: NativeTransportEventRecorder) {
        NativeTransportURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/remote-control/commands/result"):
                events.append("result")
                return try (200, CurfewProtocols.SignedRemoteCommandResultReceiptEnvelope(
                    compactJws: Self.syntheticReceiptJWS
                ).jsonData())
            case ("GET", "/sync/remote-control/commands"):
                XCTAssertEqual(events.values, ["result"])
                events.append("commands")
                return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
            default:
                return try Self.pollingResponse(for: request)
            }
        }
    }

    func installOutOfOrderStatusHandler() {
        let delays = NativeTransportResponseDelayStore()
        NativeTransportURLProtocol.handler = { request in
            guard request.url?.path == "/sync/status" else {
                return try Self.pollingResponse(for: request)
            }
            let body = try Self.requestBody(request)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let isOlderStatus = json["statusVersion"] as? Int == 18
            let proof = try XCTUnwrap(request.value(forHTTPHeaderField: "DPoP"))
            delays.set(isOlderStatus ? 0.1 : 0, for: proof)
            return (isOlderStatus ? 200 : 500, Data())
        }
        NativeTransportURLProtocol.responseDelay = { request in
            guard let proof = request.value(forHTTPHeaderField: "DPoP") else { return 0 }
            return delays.delay(for: proof)
        }
    }

    func installDelayedOverrideFailure(onRequest: @escaping () -> Void) {
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/sync/remote-overrides/active" {
                onRequest()
                return (500, Data())
            }
            return try Self.pollingResponse(for: request)
        }
        NativeTransportURLProtocol.responseDelay = { request in
            request.url?.path == "/sync/remote-overrides/active" ? 0.1 : 0
        }
    }

    static func pollingResponse(for request: URLRequest) throws -> (Int, Data) {
        switch try (request.httpMethod, XCTUnwrap(request.url?.path)) {
        case ("POST", "/sync/device-proof/challenge"):
            return challengeResponse()
        case ("GET", "/sync/devices"):
            return (200, Data("[]".utf8))
        case ("GET", "/sync/wake/status"),
             ("GET", "/sync/remote-overrides/active"):
            return (404, Data())
        case ("GET", "/sync/remote-control/commands"):
            return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
        default:
            XCTFail(
                "unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")"
            )
            return (500, Data())
        }
    }

    static func freshTokensResponse(for request: URLRequest) -> (Int, Data) {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded; charset=UTF-8"
        )
        let json = #"{"access_token":"fresh-access-token","# +
            #""refresh_token":"fresh-refresh-token","token_type":"Bearer"}"#
        return (200, Data(json.utf8))
    }

    static func challengeResponse() -> (Int, Data) {
        let json = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
            #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
        return (200, Data(json.utf8))
    }

    static func statusReport(
        deviceID: UUID,
        statusVersion: Int = 18
    ) -> DeviceStatusReport {
        DeviceStatusReport(
            deviceID: deviceID.uuidString.lowercased(),
            phase: .working,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "S", count: 43),
            statusVersion: statusVersion,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            nextTransitionAt: nil,
            activeLockoutEndsAt: nil
        )
    }

    static let syntheticReceiptJWS =
        "eyJhbGciOiJFUzI1NiJ9.e30." + String(repeating: "A", count: 86)

    func daemonResult(deviceID: UUID) throws -> Curfew.RemoteCommandResult {
        try Curfew.RemoteCommandResult(
            commandID: XCTUnwrap(
                UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")
            ),
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_000),
            appliedDeadline: Date(timeIntervalSince1970: 1_800_000_900)
        )
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func stringSecret(
        _ name: String,
        in store: NativeTransportMemorySecretStore
    ) throws -> String? {
        try store.data(for: name).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw try XCTUnwrap(stream.streamError) }
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return body
    }
}
