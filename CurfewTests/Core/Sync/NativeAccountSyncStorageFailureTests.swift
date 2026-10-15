@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testLocalEligibilityWriteFailureDoesNotRequireAccountSignIn() throws {
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
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.path
            )
        }
        XCTAssertThrowsError(try enrollmentStore.recordEligibility(
            statusVersion: 17,
            scheduleDigest: String(repeating: "S", count: 43)
        ))

        let transport = makeTransport(secrets: fixture.secrets, enrollmentStore: enrollmentStore)
        defer { transport.disconnect() }
        var signInFailures: [String] = []
        var offlineCount = 0
        transport.onFailure = { signInFailures.append($0) }
        transport.onOffline = { offlineCount += 1 }
        transport.publishDeviceStatus(
            statusReport(deviceID: fixture.deviceID), deviceID: fixture.deviceID
        )

        XCTAssertTrue(signInFailures.isEmpty)
        XCTAssertEqual(offlineCount, 1)
    }

    func testMissingLocalEnrollmentDoesNotOfferImpossibleSignInRetry() throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = makeTransport(
            secrets: fixture.secrets,
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: root.appendingPathComponent("missing-enrollment.json")
            )
        )
        defer { transport.disconnect() }
        var signInFailures: [String] = []
        var offlineCount = 0
        transport.onFailure = { signInFailures.append($0) }
        transport.onOffline = { offlineCount += 1 }

        transport.publishDeviceStatus(
            statusReport(deviceID: fixture.deviceID), deviceID: fixture.deviceID
        )

        XCTAssertEqual(signInFailures, ["Curfew cannot find this Mac’s local device identity."])
        XCTAssertEqual(offlineCount, 0)
    }

    func testCorruptLocalEnrollmentNeedsDeviceRepairInsteadOfOfflineRetry() throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recordURL = root.appendingPathComponent("corrupt-enrollment.json")
        try Data("{not valid json".utf8).write(to: recordURL)
        let transport = makeTransport(
            secrets: fixture.secrets,
            enrollmentStore: RemoteCommandEnrollmentStore(recordURL: recordURL)
        )
        defer { transport.disconnect() }
        var repairReasons: [String] = []
        var offlineCount = 0
        transport.onFailure = { repairReasons.append($0) }
        transport.onOffline = { offlineCount += 1 }

        transport.publishDeviceStatus(
            statusReport(deviceID: fixture.deviceID), deviceID: fixture.deviceID
        )

        XCTAssertEqual(repairReasons, [AccountSyncRejectionReason.localDeviceIdentityInvalid])
        XCTAssertEqual(offlineCount, 0)
    }

    func testStatusPublicationRetriesAfterLocalStorageRecovers() async throws {
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
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: root.path
            )
        }
        let prematurePost = expectation(description: "no report before local eligibility is saved")
        prematurePost.isInverted = true
        NativeTransportURLProtocol.handler = { request in
            prematurePost.fulfill()
            XCTFail("status publication unexpectedly requested \(request.url?.path ?? "unknown")")
            return (500, Data())
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets, enrollmentStore: enrollmentStore)
        defer { transport.disconnect() }
        let report = statusReport(deviceID: fixture.deviceID)

        transport.publishDeviceStatus(report, deviceID: fixture.deviceID)
        await fulfillment(of: [prematurePost], timeout: 0.1)
        XCTAssertNil(try enrollmentStore.load()?.eligibility)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let recoveredPost = expectation(description: "report after local storage recovers")
        NativeTransportURLProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/device-proof/challenge":
                return Self.challengeResponse()
            case "/sync/status":
                XCTAssertEqual(request.httpMethod, "POST")
                recoveredPost.fulfill()
                return (204, Data())
            default:
                XCTFail("unexpected request: \(request.url?.path ?? "unknown")")
                return (500, Data())
            }
        }
        replaceSessionMockBehavior()
        transport.publishDeviceStatus(report, deviceID: fixture.deviceID)
        await fulfillment(of: [recoveredPost], timeout: 1)
        XCTAssertEqual(try enrollmentStore.load()?.eligibility?.statusVersion, 17)
    }

    private func statusReport(deviceID: UUID) -> DeviceStatusReport {
        DeviceStatusReport(
            deviceID: deviceID.uuidString.lowercased(),
            phase: .dayOff,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "S", count: 43),
            statusVersion: 17,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            nextTransitionAt: nil,
            activeLockoutEndsAt: nil
        )
    }
}
