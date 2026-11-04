@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testAccountPollReadsEncryptedSettingsRecords() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let events = NativeTransportEventRecorder()
        NativeTransportURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/sync/records" {
                events.append("settings")
                return (200, Data("[]".utf8))
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertTrue(events.values.contains("settings"))
    }

    func testAccountPollRejectsRecordFromUnknownWriter() async throws {
        let fixture = try makeFixture(accessToken: "resource-bound-access-token")
        let record = CurfewProtocols.EncryptedRecord(
            aadDigest: String(repeating: "A", count: 43),
            cipherSuite: .aes256Gcm,
            ciphertext: String(repeating: "A", count: 22),
            keyEpoch: 1,
            namespace: .accountSettings,
            nonce: String(repeating: "A", count: 16),
            recordID: "018f4f45-cafe-7f00-9a82-e47805fb4d36",
            signature: String(repeating: "A", count: 86),
            signatureAlgorithm: .es256P1363Sha256,
            updatedAt: "2026-08-10T14:00:00Z",
            version: 1,
            writerCounter: 1,
            writerDeviceID: "018f4f45-cafe-7f00-9a82-e47805fb4d37"
        )
        let payload = try JSONEncoder().encode([record])
        NativeTransportURLProtocol.handler = { request in
            if request.httpMethod == "GET", request.url?.path == "/sync/records" {
                return (200, payload)
            }
            return try Self.pollingResponse(for: request)
        }
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets)
        var failed = false
        transport.onOffline = { failed = true }

        await transport.pollOnce(deviceID: fixture.deviceID)

        XCTAssertTrue(failed, "An unknown writer must not be accepted as a settings source")
    }
}
