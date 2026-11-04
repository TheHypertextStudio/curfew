@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testSignedRecordWithInvalidScheduleIsRejected() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let keys = try XCTUnwrap(AccountDeviceKeyStore(secretStore: fixture.secrets)
            .load(deviceID: fixture.deviceID))
        let record = try AccountRecordCrypto().seal(
            ["unexpected": "value"], namespace: .accountSettings,
            recordID: XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")),
            version: 1, writerCounter: 1, writerDeviceID: fixture.deviceID, keyEpoch: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000), keys: keys
        )
        let peer = CurfewProtocols.AccountDeviceEnrollment(
            deviceID: fixture.deviceID.uuidString.lowercased(),
            encryptionPublicKeyJwk: validationKey(keys.encryptionPublicKey),
            enrolledAt: "2026-08-10T14:00:00Z", keyEpoch: 1, protocolVersion: "0.0",
            signingPublicKeyJwk: validationKey(keys.signingPublicKey)
        )
        let records = try JSONEncoder().encode([record])
        let peers = try JSONEncoder().encode([peer])
        NativeTransportURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/sync/records" {
                return (200, records)
            }
            if request.httpMethod == "GET", request.url?.path == "/sync/devices" {
                return (200, peers)
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        var failed = false
        transport.onOffline = { failed = true }

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertTrue(failed, "Malformed encrypted schedules must fail closed")
    }

    private func validationKey(_ key: AccountPublicKeyJWK) -> CurfewProtocols.AccountPublicKeyJWK {
        CurfewProtocols.AccountPublicKeyJWK(crv: .p256, kty: .ec, x: key.x, y: key.y)
    }
}
