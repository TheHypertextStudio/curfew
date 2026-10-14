@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testCancelledStatusPublicationDoesNotSuppressNextHeartbeat() throws {
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
        defer { transport.disconnect() }
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
        transport.stopNetworkActivity()
        var heartbeat = first
        heartbeat.statusVersion = 18
        heartbeat.observedAt = first.observedAt.addingTimeInterval(60)

        transport.publishDeviceStatus(heartbeat, deviceID: fixture.deviceID)

        XCTAssertEqual(try enrollmentStore.load()?.eligibility?.statusVersion, 18)
    }
}
