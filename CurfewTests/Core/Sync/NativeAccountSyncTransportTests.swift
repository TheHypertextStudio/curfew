@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncTransportTests: XCTestCase {
    func testUnchangedInFlightHeartbeatKeepsEligibleStatusVersion() throws {
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
        let transport = makeTransport(secrets: fixture.secrets, enrollmentStore: enrollmentStore)
        let first = DeviceStatusReport(
            deviceID: fixture.deviceID.uuidString.lowercased(),
            phase: .working,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "S", count: 43),
            statusVersion: 17,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            nextTransitionAt: nil,
            activeLockoutEndsAt: nil
        )
        transport.publishDeviceStatus(first, deviceID: fixture.deviceID)
        var heartbeat = first
        heartbeat.statusVersion = 18
        heartbeat.observedAt = first.observedAt.addingTimeInterval(60)

        transport.publishDeviceStatus(heartbeat, deviceID: fixture.deviceID)

        XCTAssertEqual(try enrollmentStore.load()?.eligibility?.statusVersion, 17)
        transport.disconnect()
    }
}

extension NativeAccountSyncTransportTests {
    func testStalePollCannotStartAnOperationAfterDisconnect() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let transport = makeTransport(secrets: fixture.secrets)
        let generation = transport.connectionGeneration
        transport.disconnect()
        var operations = 0

        let succeeded = await transport.pollWithRefresh(
            deviceID: fixture.deviceID, channel: .deviceStatus, generation: generation
        ) {
            operations += 1
        }

        XCTAssertFalse(succeeded)
        XCTAssertEqual(operations, 0)
    }

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
        defer { transport.disconnect() }
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

    func testPollClearsAnOverrideAndReportsAHealthyConnectionWithoutAWakeCampaign() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let confirmedAt = Date(timeIntervalSince1970: 1_800_000_123)
        let cleared = expectation(description: "inactive remote override cleared")
        let completed = expectation(description: "poll completed")
        let synchronized = expectation(description: "authenticated poll reported healthy")
        installPollingHandler(
            batch: RemoteCommandDeliveryBatch(commands: []),
            onCommands: { completed.fulfill() }
        )
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets, now: { confirmedAt })

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { date in
                    XCTAssertEqual(date, confirmedAt)
                    synchronized.fulfill()
                },
                onOffline: {},
                onWakeStatus: { _ in },
                onRemoteOverride: { override in
                    XCTAssertNil(override)
                    cleared.fulfill()
                },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )

        await fulfillment(of: [cleared, completed, synchronized], timeout: 1)
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
        let offline = expectation(description: "wake failure reported after override clear")
        let synchronized = expectation(description: "partial poll must not report healthy")
        synchronized.isInverted = true

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in synchronized.fulfill() },
                onOffline: { offline.fulfill() },
                onWakeStatus: { _ in },
                onRemoteOverride: { override in
                    XCTAssertNil(override)
                    cleared.fulfill()
                },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )

        await fulfillment(of: [cleared, offline, synchronized], timeout: 0.2)
        transport.disconnect()
    }

    func testOverrideFailureCannotBeOverwrittenByAHealthyAccountPoll() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let accountPollCompleted = expectation(description: "account poll completed")
        let offline = expectation(description: "override failure reported offline")
        let synchronized = expectation(description: "partial poll must not report healthy")
        synchronized.isInverted = true
        installPollingHandler(
            batch: RemoteCommandDeliveryBatch(commands: []),
            onCommands: { accountPollCompleted.fulfill() }
        )
        let baseHandler = try XCTUnwrap(NativeTransportURLProtocol.handler)
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/sync/remote-overrides/active" {
                return (500, Data())
            }
            return try baseHandler(request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in synchronized.fulfill() },
                onOffline: { offline.fulfill() },
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )

        await fulfillment(of: [accountPollCompleted, offline, synchronized], timeout: 0.2)
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

    func testScheduledCommandsWaitWhileResultPublicationFails() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exchange = RemoteCommandResultExchangeStore(
            resultsURL: root.appendingPathComponent("results.json"),
            acknowledgementsDirectoryURL: root.appendingPathComponent("ack", isDirectory: true)
        )
        try exchange.publish([daemonResult(deviceID: fixture.deviceID)])
        let resultAttempted = expectation(description: "terminal result publication attempted")
        resultAttempted.assertForOverFulfill = false
        let commands = expectation(description: "no commands past unreported result")
        commands.isInverted = true
        commands.assertForOverFulfill = false
        NativeTransportURLProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/remote-control/commands/result":
                resultAttempted.fulfill()
                return (503, Data())
            case "/sync/remote-control/commands":
                Task { @MainActor in commands.fulfill() }
                return try Self.pollingResponse(for: request)
            default:
                return try Self.pollingResponse(for: request)
            }
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(
            secrets: fixture.secrets,
            inboxStore: RemoteCommandInboxStore(
                directoryURL: root.appendingPathComponent("inbox", isDirectory: true)
            ),
            resultExchangeStore: exchange,
            pollingInterval: .milliseconds(20)
        )
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in }, onOffline: {}, onWakeStatus: { _ in },
                onRemoteOverride: { _ in }, onRemoteCommandResult: { _ in }, onFailure: { _ in }
            )
        )
        await fulfillment(of: [resultAttempted], timeout: 1)
        await fulfillment(of: [commands], timeout: 0.1)
        transport.disconnect()
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
        // The daemon discards an unverifiable receipt without removing its result.
        // The next reconciliation must obtain a fresh receipt, not suppress it forever.
        try exchange.removeReceipt(for: result)
        await transport.pollOnce(deviceID: fixture.deviceID)
        XCTAssertEqual(events.values, ["result", "commands", "result", "commands"])
        XCTAssertNotNil(try exchange.pendingReceipt(for: result))
    }
}
