import Foundation
import XCTest
@testable import Curfew

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
            recordID: UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")!,
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

        XCTAssertFalse(String(decoding: encodedRecord, as: UTF8.self).contains("standardNineToFive"))
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
}

private final class MemoryAccountSecretStore: AccountSecretStoring {
    private(set) var records: [String: Data] = [:]
    var values: [Data] { Array(records.values) }

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
