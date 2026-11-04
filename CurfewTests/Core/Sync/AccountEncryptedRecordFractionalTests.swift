import CryptoKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

@MainActor
final class AccountEncryptedRecordFractionalTests: XCTestCase {
    func testDecryptsRecordWithFractionalTimestampAndMatchingAAD() throws {
        let deviceID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35"))
        let recordID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36"))
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000.125)
        let store = AccountDeviceKeyStore(secretStore: NativeTransportMemorySecretStore())
        _ = try store.createEnrollment(deviceID: deviceID, keyEpoch: 1, createdAt: timestamp)
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        let header = makeHeader(deviceID: deviceID, recordID: recordID, timestamp: timestamp)
        let aad = try JSONSerialization.data(
            withJSONObject: header, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let key = namespaceKey(keys.accountRootKey)
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 0x72, count: 12))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let settings = CurfewSettings.default
        let sealed = try AES.GCM.seal(
            encoder.encode(settings),
            using: key,
            nonce: nonce,
            authenticating: aad
        )
        let ciphertext = base64URL(sealed.ciphertext + sealed.tag)
        let digest = base64URL(Data(SHA256.hash(data: aad)))
        let nonceText = base64URL(Data(nonce))
        var signed = header
        signed["aadDigest"] = digest
        signed["ciphertext"] = ciphertext
        signed["nonce"] = nonceText
        signed["signatureAlgorithm"] = "ES256-P1363-SHA256"
        let signatureInput = try JSONSerialization.data(
            withJSONObject: signed, options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let signingKey = try P256.Signing.PrivateKey(rawRepresentation: keys.signingPrivateKey)
        let signature = try base64URL(signingKey.signature(for: signatureInput).rawRepresentation)
        let record = AccountEncryptedRecord(
            namespace: .accountSettings, recordID: recordID, version: 1,
            writerDeviceID: deviceID, writerCounter: 1, keyEpoch: 1, cipherSuite: "AES-256-GCM",
            nonce: nonceText, aadDigest: digest, ciphertext: ciphertext,
            signatureAlgorithm: "ES256-P1363-SHA256", signature: signature, updatedAt: timestamp
        )

        let result = try AccountRecordCrypto().open(
            record, as: CurfewSettings.self, accountRootKey: keys.accountRootKey,
            signingPublicKey: keys.signingPublicKey
        )

        XCTAssertEqual(result, settings)
    }

    private func makeHeader(deviceID: UUID, recordID: UUID, timestamp: Date) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            "cipherSuite": "AES-256-GCM", "keyEpoch": 1, "namespace": "account_settings",
            "recordId": recordID.uuidString.lowercased(),
            "updatedAt": formatter.string(from: timestamp), "version": 1, "writerCounter": 1,
            "writerDeviceId": deviceID.uuidString.lowercased()
        ]
    }

    private func namespaceKey(_ rootKey: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: rootKey),
            salt: Data("curfew-encrypted-record-v2".utf8),
            info: Data("namespace=account_settings;keyEpoch=1".utf8),
            outputByteCount: 32
        )
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
