@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testOlderSignedRecordCannotRollBackAcceptedSettingsVersion() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let store = AccountDeviceKeyStore(secretStore: fixture.secrets)
        let keys = try XCTUnwrap(store.load(deviceID: fixture.deviceID))
        let recordID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36"))
        let crypto = AccountRecordCrypto()
        let newer = try crypto.seal(
            ScheduleFixture(lockTime: "22:00"), namespace: .accountSettings, recordID: recordID,
            version: 2, writerCounter: 2, writerDeviceID: fixture.deviceID, keyEpoch: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000), keys: keys
        )
        let older = try crypto.seal(
            ScheduleFixture(lockTime: "23:00"), namespace: .accountSettings, recordID: recordID,
            version: 1, writerCounter: 1, writerDeviceID: fixture.deviceID, keyEpoch: 1,
            updatedAt: Date(timeIntervalSince1970: 1_799_999_999), keys: keys
        )
        let peer = CurfewProtocols.AccountDeviceEnrollment(
            deviceID: fixture.deviceID.uuidString.lowercased(),
            encryptionPublicKeyJwk: generatedKey(keys.encryptionPublicKey),
            enrolledAt: "2026-08-10T14:00:00Z", keyEpoch: 1, protocolVersion: "0.0",
            signingPublicKeyJwk: generatedKey(keys.signingPublicKey)
        )
        let peerData = try JSONEncoder().encode([peer])
        let newerData = try JSONEncoder().encode([newer])
        let olderData = try JSONEncoder().encode([older])
        let reads = NativeTransportEventRecorder()
        NativeTransportURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/sync/records" {
                reads.append("record")
                return (200, reads.values.count == 1 ? newerData : olderData)
            }
            if request.httpMethod == "GET", request.url?.path == "/sync/devices" {
                return (200, peerData)
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        var failed = false
        transport.onOffline = { failed = true }

        await transport.pollOnce(deviceID: fixture.deviceID)
        XCTAssertFalse(failed)
        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertTrue(failed, "A signed older record must not roll settings back")
    }

    private func generatedKey(
        _ key: Curfew.AccountPublicKeyJWK
    ) -> CurfewProtocols.AccountPublicKeyJWK {
        CurfewProtocols.AccountPublicKeyJWK(crv: .p256, kty: .ec, x: key.x, y: key.y)
    }
}

private struct ScheduleFixture: Encodable {
    private struct Day: Encodable {
        let isDayOff = false
        let lockTime: String
        let mode = "time"
        let unlockTime = "05:00"
    }

    private let schemaVersion = 1
    private let days: [String: Day]

    init(lockTime: String) {
        let day = Day(lockTime: lockTime)
        self.days = Dictionary(uniqueKeysWithValues: [
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
        ].map { ($0, day) })
    }
}
