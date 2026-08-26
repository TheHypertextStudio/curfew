@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class AccountEncryptionTests: XCTestCase {
    private let deviceID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testEnrollmentStoresPrivateMaterialButNeverRecoveryKey() throws {
        let secrets = MemoryAccountSecretStore()
        let store = AccountDeviceKeyStore(secretStore: secrets)

        let bootstrap = try store.createEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            createdAt: createdAt
        )
        let loaded = try XCTUnwrap(store.load(deviceID: deviceID))
        let recoveredRoot = try AccountRecoveryCrypto.unwrap(
            bootstrap.recoveryEnvelope,
            recoveryKey: bootstrap.recoveryKey
        )

        XCTAssertEqual(loaded.accountRootKey.count, 32)
        XCTAssertEqual(recoveredRoot, loaded.accountRootKey)
        XCTAssertNotEqual(Data(bootstrap.recoveryKey.utf8), loaded.accountRootKey)
        XCTAssertFalse(secrets.values.contains(Data(bootstrap.recoveryKey.utf8)))
        XCTAssertEqual(bootstrap.encryptionPublicKey.x.count, 43)
        XCTAssertEqual(bootstrap.signingPublicKey.y.count, 43)
    }

    func testSettingsRecordIsNamespaceEncryptedSignedAndRoundTrips() throws {
        let store = AccountDeviceKeyStore(secretStore: MemoryAccountSecretStore())
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: createdAt)
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        let crypto = AccountRecordCrypto()

        let record = try crypto.seal(
            settings,
            namespace: .accountSettings,
            recordID: XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")),
            version: 1,
            writerCounter: 1,
            writerDeviceID: deviceID,
            keyEpoch: 1,
            updatedAt: createdAt,
            keys: keys
        )
        let encodedRecord = try JSONEncoder().encode(record)
        let decoded = try crypto.open(
            record,
            as: CurfewSettings.self,
            accountRootKey: keys.accountRootKey,
            signingPublicKey: keys.signingPublicKey
        )

        XCTAssertFalse(
            String(bytes: encodedRecord, encoding: .utf8)?.contains("standardNineToFive") == true
        )
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(record.cipherSuite, "AES-256-GCM")
        XCTAssertEqual(record.signatureAlgorithm, "ES256-P1363-SHA256")
        XCTAssertEqual(record.aadDigest.count, 43)
    }

    func testTamperedRecordFailsClosed() throws {
        let store = AccountDeviceKeyStore(secretStore: MemoryAccountSecretStore())
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: createdAt)
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        let crypto = AccountRecordCrypto()
        let record = try crypto.seal(
            ["wake": "pending"],
            namespace: .campaigns,
            recordID: UUID(),
            version: 3,
            writerCounter: 9,
            writerDeviceID: deviceID,
            keyEpoch: 1,
            updatedAt: createdAt,
            keys: keys
        )
        let tampered = record.replacing(ciphertext: record.ciphertext + "A")

        XCTAssertThrowsError(
            try crypto.open(
                tampered,
                as: [String: String].self,
                accountRootKey: keys.accountRootKey,
                signingPublicKey: keys.signingPublicKey
            )
        )
    }

    func testRecoveryReplacesOnlyTheProvisionalRootKey() throws {
        let secrets = MemoryAccountSecretStore()
        let store = AccountDeviceKeyStore(secretStore: secrets)
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: createdAt)
        let provisional = try XCTUnwrap(store.load(deviceID: deviceID))
        let recoveredRoot = Data(repeating: 0x7A, count: 32)

        try store.replaceAccountRootKey(recoveredRoot, deviceID: deviceID)

        let restored = try XCTUnwrap(store.load(deviceID: deviceID))
        XCTAssertEqual(restored.accountRootKey, recoveredRoot)
        XCTAssertEqual(restored.signingPrivateKey, provisional.signingPrivateKey)
        XCTAssertEqual(restored.encryptionPrivateKey, provisional.encryptionPrivateKey)
    }

    func testGeneratedRecoveryEnvelopeRoundTripsWithoutChangingCryptoInput() throws {
        let store = AccountDeviceKeyStore(secretStore: MemoryAccountSecretStore())
        let bootstrap = try store.createEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            createdAt: createdAt
        )
        let generated = AccountRecoveryEnvelopeBridge.generated(bootstrap.recoveryEnvelope)
        let local = try AccountRecoveryEnvelopeBridge.local(generated)

        XCTAssertEqual(generated.info, .curfewRecoveryWrapV2)
        XCTAssertEqual(
            try AccountRecoveryCrypto.unwrap(local, recoveryKey: bootstrap.recoveryKey),
            try XCTUnwrap(store.load(deviceID: deviceID)).accountRootKey
        )
    }

    func testRootEnvelopeSealingMatchesTheSharedHPKEVector() throws {
        let recipientID = "018f4f45-a055-7502-8b0c-7276bfe16c8f"
        let recipient = CurfewProtocols.AccountDeviceEnrollment(
            deviceID: recipientID,
            encryptionPublicKeyJwk: CurfewProtocols.AccountPublicKeyJWK(
                crv: .p256,
                kty: .ec,
                x: "fPJ7GI0DT36KUjgDBLUaw8CJaeJ38hs1pgtI_EdmmXg",
                y: "B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E"
            ),
            enrolledAt: "2026-08-10T14:00:00Z",
            keyEpoch: 1,
            protocolVersion: "0.3",
            signingPublicKeyJwk: CurfewProtocols.AccountPublicKeyJWK(
                crv: .p256,
                kty: .ec,
                x: "fPJ7GI0DT36KUjgDBLUaw8CJaeJ38hs1pgtI_EdmmXg",
                y: "B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E"
            )
        )
        let envelope = try AccountRootKeyEnvelopeCrypto.seal(
            rootKey: decode("ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"),
            recipient: recipient,
            createdAt: XCTUnwrap(
                ISO8601DateFormatter().date(from: "2026-08-10T14:00:00Z")
            ),
            ephemeralPrivateKey: decode("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM")
        )

        XCTAssertEqual(
            envelope.encapsulatedKey,
            "BF7L5NGmMwpEyPfvlR1L8WXmxrch762phftBZhvG5_1s" +
                "hzRkDEmY_343SwbOGmSi7NgqsDY4T7g9mnmxJ6J9UDI"
        )
        XCTAssertEqual(
            envelope.ciphertext,
            "zR1Y5Z8iG09FOfMi_3cmndteDPYsKv7_03STWS4C8yvY5ZGpGoYkTqHTjy-lXrpD"
        )
    }

    func testIncompleteRecoveryEnrollmentSurvivesRelaunchUntilAcknowledged() throws {
        let secrets = MemoryAccountSecretStore()
        let pending = AccountEnrollmentPendingStore(secretStore: secrets)
        let enrollment = AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            enrolledAt: createdAt
        )

        try pending.save(enrollment: enrollment, recoveryKey: "recovery-key")
        XCTAssertEqual(
            try pending.load(),
            .saveRecoveryKey("recovery-key", enrollment)
        )

        try pending.clear()
        XCTAssertNil(try pending.load())
    }
}

private func decode(_ value: String) -> Data {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)!
}

private final class MemoryAccountSecretStore: AccountSecretStoring {
    private(set) var records: [String: Data] = [:]
    var values: [Data] {
        Array(records.values)
    }

    func data(for account: String) throws -> Data? {
        records[account]
    }

    func save(_ data: Data, for account: String) throws {
        records[account] = data
    }

    func delete(_ account: String) throws {
        records.removeValue(forKey: account)
    }
}
