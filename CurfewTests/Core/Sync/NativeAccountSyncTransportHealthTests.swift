@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testRootKeyDistributionFailureCannotBeOverwrittenByAHealthyAccountPoll() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/sync/devices" {
                return (500, Data())
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        let offline = expectation(description: "root-key distribution failure reported offline")
        let synchronized = expectation(description: "failed account poll must not report healthy")
        synchronized.isInverted = true

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

        await fulfillment(of: [offline, synchronized], timeout: 0.2)
        transport.disconnect()
    }

    func testFailedStatusPublicationRemainsUnhealthyAfterSuccessfulPolls() async throws {
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
        let synchronized = expectation(description: "initial polls reported healthy")
        let offline = expectation(description: "status publication failure reported offline")
        var synchronizationCount = 0
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/sync/status" {
                return (500, Data())
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(
            secrets: fixture.secrets,
            enrollmentStore: enrollmentStore
        )
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in
                    synchronizationCount += 1
                    synchronized.fulfill()
                },
                onOffline: { offline.fulfill() },
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )
        await fulfillment(of: [synchronized], timeout: 1)

        transport.publishDeviceStatus(
            Self.statusReport(deviceID: fixture.deviceID),
            deviceID: fixture.deviceID
        )
        await fulfillment(of: [offline], timeout: 1)
        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertEqual(synchronizationCount, 1)
        transport.disconnect()
    }

    func testRejectedRefreshTokenRequiresSignInInsteadOfReportingOffline() async throws {
        let fixture = try makeFixture(
            accessToken: "expired-access-token",
            refreshToken: "revoked-refresh-token",
            clientID: "curfew-native-client"
        )
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/oauth2/token" {
                return (400, Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            return (401, Data())
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        let rejected = expectation(description: "revoked refresh token requires sign-in")
        rejected.expectedFulfillmentCount = 2
        let offline = expectation(description: "permanent credential rejection is not offline")
        offline.isInverted = true

        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in },
                onOffline: { offline.fulfill() },
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { reason in
                    XCTAssertEqual(reason, "Curfew needs you to sign in again.")
                    rejected.fulfill()
                }
            )
        )

        await fulfillment(of: [rejected, offline], timeout: 0.2)
        transport.disconnect()
    }

    func testOlderStatusSuccessCannotOverwriteTheLatestStatusFailure() async throws {
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
        installOutOfOrderStatusHandler()
        defer {
            NativeTransportURLProtocol.handler = nil
            NativeTransportURLProtocol.responseDelay = nil
        }
        let synchronized = expectation(description: "initial polls reported healthy")
        let offline = expectation(description: "latest status publication failed")
        var synchronizationCount = 0
        let transport = makeTransport(
            secrets: fixture.secrets,
            enrollmentStore: enrollmentStore
        )
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in
                    synchronizationCount += 1
                    synchronized.fulfill()
                },
                onOffline: { offline.fulfill() },
                onWakeStatus: { _ in },
                onRemoteOverride: { _ in },
                onRemoteCommandResult: { _ in },
                onFailure: { _ in }
            )
        )
        await fulfillment(of: [synchronized], timeout: 1)

        transport.publishDeviceStatus(
            Self.statusReport(deviceID: fixture.deviceID, statusVersion: 18),
            deviceID: fixture.deviceID
        )
        transport.publishDeviceStatus(
            Self.statusReport(deviceID: fixture.deviceID, statusVersion: 19),
            deviceID: fixture.deviceID
        )
        await fulfillment(of: [offline], timeout: 1)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(synchronizationCount, 1)
        transport.disconnect()
    }

    func testReconnectIgnoresFailureFromThePreviousPollingSession() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let oldRequestStarted = expectation(description: "old override poll started")
        installDelayedOverrideFailure { oldRequestStarted.fulfill() }
        defer {
            NativeTransportURLProtocol.handler = nil
            NativeTransportURLProtocol.responseDelay = nil
        }
        let transport = makeTransport(secrets: fixture.secrets)
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in }, onOffline: {}, onWakeStatus: { _ in },
                onRemoteOverride: { _ in }, onRemoteCommandResult: { _ in }, onFailure: { _ in }
            )
        )
        await fulfillment(of: [oldRequestStarted], timeout: 1)
        transport.disconnect()

        installPollingHandler(batch: RemoteCommandDeliveryBatch(commands: []))
        NativeTransportURLProtocol.responseDelay = nil
        let synchronized = expectation(description: "new polling session reported healthy")
        let offline = expectation(description: "old failure did not reach the new session")
        offline.isInverted = true
        transport.connect(
            deviceID: fixture.deviceID,
            callbacks: AccountSyncTransportCallbacks(
                onSynchronized: { _ in synchronized.fulfill() },
                onOffline: { offline.fulfill() }, onWakeStatus: { _ in },
                onRemoteOverride: { _ in }, onRemoteCommandResult: { _ in }, onFailure: { _ in }
            )
        )

        await fulfillment(of: [synchronized, offline], timeout: 0.2)
        transport.disconnect()
    }
}
