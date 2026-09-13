@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncTransportTests: XCTestCase {
    func testStatusPublicationRecordsTheExactLocalEligibilitySnapshot() throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let enrollmentStore = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("enrollment.json")
        )
        try enrollmentStore.save(RemoteCommandEnrollment(
            userID: "account_018f4f45cafe7f009a82e47805fb4d34",
            deviceID: fixture.deviceID
        ))
        let transport = makeTransport(
            secrets: fixture.secrets,
            enrollmentStore: enrollmentStore
        )
        let report = DeviceStatusReport(
            deviceID: fixture.deviceID.uuidString.lowercased(),
            phase: .warning,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "S", count: 43),
            statusVersion: 17,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            nextTransitionAt: nil,
            activeLockoutEndsAt: nil
        )

        transport.publishDeviceStatus(report, deviceID: fixture.deviceID)

        XCTAssertEqual(
            try enrollmentStore.load()?.eligibility,
            RemoteCommandEligibilitySnapshot(
                statusVersion: 17,
                scheduleDigest: String(repeating: "S", count: 43)
            )
        )
    }

    func testPollStagesRemoteCommandsForPrivilegedVerification() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = RemoteCommandInboxStore(directoryURL: root)
        let delivery = RemoteCommandDelivery(
            commandEnvelope: CommandCommandEnvelope(compactJws: "header.payload.signature"),
            cursor: "cursor_018f4f45cafe7f009a82e47805fb4d34",
            type: .command
        )
        installPollingHandler(batch: RemoteCommandDeliveryBatch(commands: [delivery]))
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets, inboxStore: inbox)

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertEqual(try inbox.pendingDeliveries(), [
            PendingRemoteCommandDelivery(
                cursor: delivery.cursor,
                envelope: SignedRemoteLockoutCommandEnvelope(
                    compactJWS: "header.payload.signature"
                )
            )
        ])
    }

    func testPollClearsAnOverrideThatIsNoLongerActive() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let cleared = expectation(description: "inactive remote override cleared")
        let completed = expectation(description: "poll completed")
        installPollingHandler(
            batch: RemoteCommandDeliveryBatch(commands: []),
            onCommands: { completed.fulfill() }
        )
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)

        transport.connect(
            deviceID: fixture.deviceID,
            onWakeStatus: { _ in },
            onRemoteOverride: { override in
                XCTAssertNil(override)
                cleared.fulfill()
            },
            onRemoteCommandResult: { _ in },
            onFailure: { _ in }
        )

        await fulfillment(of: [cleared, completed], timeout: 1)
        transport.disconnect()
    }

    func testPollDeliversCoordinatorOverrideWithFractionalTimestamp() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let startsAt = "2026-09-05T08:30:00.000Z"
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/sync/remote-overrides/active" {
                let json = #"{"authorizedBy":"mcp_preauthorized_client","durationMinutes":30,"overrideId":"018f4f45-cafe-7f00-9a82-e47805fb4d36","reason":"Finish an active remote maintenance session.","requestId":"018f4f45-cafe-7f00-9a82-e47805fb4d37","startsAt":"\#(startsAt)","status":"active","targetDeviceIds":["\#(fixture.deviceID.uuidString.lowercased())"]}"#
                return (200, Data(json.utf8))
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)

        let override = try await transport.fetchRemoteOverride(deviceID: fixture.deviceID)

        XCTAssertEqual(
            override?.startsAt,
            ISO8601DateFormatter().date(from: "2026-09-05T08:30:00Z")
        )
    }

    func testPollClearsAnOverrideWhenWakeStatusFails() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        NativeTransportURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            switch (request.httpMethod, path) {
            case ("POST", "/sync/device-proof/challenge"):
                return Self.challengeResponse()
            case ("GET", "/sync/devices"):
                return (200, Data("[]".utf8))
            case ("GET", "/sync/wake/status"):
                return (500, Data())
            case ("GET", "/sync/remote-overrides/active"):
                return (404, Data())
            case ("GET", "/sync/remote-control/commands"):
                return try (200, RemoteCommandDeliveryBatch(commands: []).jsonData())
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path)")
                return (500, Data())
            }
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        let cleared = expectation(description: "inactive override cleared despite wake failure")
        let failed = expectation(description: "wake failure reported after override clear")

        transport.connect(
            deviceID: fixture.deviceID,
            onWakeStatus: { _ in },
            onRemoteOverride: { override in
                XCTAssertNil(override)
                cleared.fulfill()
            },
            onRemoteCommandResult: { _ in },
            onFailure: { _ in failed.fulfill() }
        )

        await fulfillment(of: [cleared, failed], timeout: 1)
        transport.disconnect()
    }

    func testExpiredAccessTokenRefreshesAndRetriesPoll() async throws {
        let fixture = try makeFixture(
            accessToken: "expired-access-token",
            refreshToken: "rotating-refresh-token",
            clientID: "curfew-native-client"
        )
        let events = NativeTransportEventRecorder()
        installRefreshHandler(events: events)
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertEqual(events.values, ["expired", "refresh", "commands"])
        XCTAssertEqual(
            try stringSecret("oauth-access-token", in: fixture.secrets),
            "fresh-access-token"
        )
        XCTAssertEqual(
            try stringSecret("oauth-refresh-token", in: fixture.secrets),
            "fresh-refresh-token"
        )
    }

    func testPollPublishesDaemonResultBeforeFetchingMoreCommands() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        let result = try daemonResult(deviceID: fixture.deviceID)
        try exchange.publish([result])
        let events = NativeTransportEventRecorder()
        installResultHandler(events: events)
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(
            secrets: fixture.secrets,
            inboxStore: RemoteCommandInboxStore(
                directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
            ),
            resultExchangeStore: exchange
        )

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertEqual(events.values, ["result", "commands"])
        XCTAssertEqual(
            try exchange.pendingReceipt(for: result)?.compactJWS,
            Self.syntheticReceiptJWS
        )
    }
}

private extension NativeAccountSyncTransportTests {
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

    private func makeTransport(
        secrets: NativeTransportMemorySecretStore,
        inboxStore: RemoteCommandInboxStore? = nil,
        resultExchangeStore: RemoteCommandResultExchangeStore? = nil,
        enrollmentStore: RemoteCommandEnrollmentStore? = nil,
        pollingInterval: Duration = .seconds(15)
    ) -> NativeAccountSyncTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeTransportURLProtocol.self]
        return NativeAccountSyncTransport(
            secretStore: secrets,
            session: URLSession(configuration: configuration),
            inboxStore: inboxStore,
            resultExchangeStore: resultExchangeStore,
            enrollmentStore: enrollmentStore,
            pollingInterval: pollingInterval
        )
    }

    private func installPollingHandler(
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

    private func installRefreshHandler(events: NativeTransportEventRecorder) {
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

    private func installResultHandler(events: NativeTransportEventRecorder) {
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

    private static func pollingResponse(for request: URLRequest) throws -> (Int, Data) {
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

    private static func freshTokensResponse(for request: URLRequest) -> (Int, Data) {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded; charset=UTF-8"
        )
        let json = #"{"access_token":"fresh-access-token","# +
            #""refresh_token":"fresh-refresh-token","token_type":"Bearer"}"#
        return (200, Data(json.utf8))
    }

    private static func challengeResponse() -> (Int, Data) {
        let json = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
            #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":1}"#
        return (200, Data(json.utf8))
    }

    private static let syntheticReceiptJWS =
        "eyJhbGciOiJFUzI1NiJ9.e30." + String(repeating: "A", count: 86)

    private func daemonResult(deviceID: UUID) throws -> Curfew.RemoteCommandResult {
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func stringSecret(
        _ name: String,
        in store: NativeTransportMemorySecretStore
    ) throws -> String? {
        try store.data(for: name).flatMap { String(data: $0, encoding: .utf8) }
    }
}
