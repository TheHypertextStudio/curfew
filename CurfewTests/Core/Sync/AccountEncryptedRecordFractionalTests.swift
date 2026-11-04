import CryptoKit
@testable import Curfew
@testable import CurfewKit
import CurfewProtocols
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

    func testSharedVectorDecryptsWithExactZeroFraction() throws {
        let ciphertext =
            "o1bmF3GMXado1OovG5rM-DVgENlQ3gxf5KnONv3_9xmQs2xRbDUvf1ZF_wOKBv19VGGhZn" +
            "aXeiezfU6LuyR0tD1qKhdl-vfS" +
            "P002O6VabKu5Q61XX0sn4lUl-qT1xDkMuaDkOKuzolkE2hPZ6CiXeGOZJKT69c3_McZdrD" +
            "npIsF2uj0fSmPSoyT2-rcutb4x" +
            "m8wQefQmsQ3doXJy8hgeFAxIbpqZHoXHZDFouo25gWI8Y0X95D3qgBOrMLUIV2Xzc1jkhd" +
            "hCnYitrWFpcAKHs4PTgtJOYAaQ" +
            "S3dBgfz8hPZwc5BoZg1TiZKUXWlLUYR31AVnHWqm_DzNb21wLQjqaxjbBrtBv80N5DyF1i" +
            "Ju55nLjOJCrFMf9JRPTNMenk1o" +
            "pm6ARxu2N6vlUkUdUJcMbS2emWHGCd-b-T93zDc07JUmIhFIeXbesBNwtk7bXgRfQLoK8_" +
            "CfHjwKJJYsX-M_-EI1ilHec6Ne" +
            "ewJX1QZo6gMMKUvA39cUn8Pclgr43E_38gZ5h1yB1gwN_pmciEq3C04S8bR-_8xjYOMS9Z" +
            "fnkT5kKOUxeG7WnY_mPM1LaoDq" +
            "aa_9RvrBKYHpb1Km7ATcsJMnK3HpeyK2USbzNhhcbU8klldZLNE9-Jp20PNz6I7CgyM3fG" +
            "hLsOy4cFui2BYms8X4gWpGWgMC" +
            "dPMpHhs45U_YDOYsTF2O_iI75DwOMArwrm5yNa-MC4LVd1wfPQlrKOnfZE44AWu5rNuf7n" +
            "gWTdv7xHlpOoMyRaj6QcpkLcZs" +
            "H_W3ToFE1b2_AOjTi0kd5lK7xsxNvLlyf-_j8GqvTfdEBw-M5f2E9UcnSXs_bK_Ps6wAfJ" +
            "NJkFfosFqtXM4kJnm3XLM7b9BU" +
            "wMQlQTPRyrtEGhy92_jxL4KNHVp5riPMKINgIenGiOLqApe2i86sBv3DgoSBgjoBFS18cA" +
            "CQJCjiNbTGES48ItY0QaRaMA"
        let wire = CurfewProtocols.EncryptedRecord(
            aadDigest: "T1l_CkVGoYWg_wRfCABoxIApqridBZMH27kxSdj1puo", cipherSuite: .aes256Gcm,
            ciphertext: ciphertext, keyEpoch: 1, namespace: .accountSettings,
            nonce: "oKGio6Slpqeoqaqr",
            recordID: "018f4f45-4d34-7d98-a6c5-4de1bd63a21c",
            signature: "HyHYoc-ta97BlmOlksJreh1LLlbIpElJaKGDK2oa9FFpzeWcv7nkbiRxSuvpOseMkuceWZ" +
                "F2weFj7ir8Qwr4kw",
            signatureAlgorithm: .es256P1363Sha256,
            updatedAt: "2026-08-10T14:00:00.000Z", version: 1, writerCounter: 1,
            writerDeviceID: "018f4f45-a055-7502-8b0c-7276bfe16c8f"
        )
        let record = try AccountEncryptedRecord.fromWire(wire)
        let rootKey = try XCTUnwrap(decodeBase64URL("ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"))
        let publicKey = Curfew.AccountPublicKeyJWK(
            xCoordinate: "axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpY",
            yCoordinate: "T-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU"
        )
        let result = try AccountRecordCrypto().open(
            record, as: ScheduleVersion.self, accountRootKey: rootKey, signingPublicKey: publicKey
        )
        XCTAssertEqual(result.schemaVersion, 1)
    }

    private struct ScheduleVersion: Decodable {
        let schemaVersion: Int
    }

    private func decodeBase64URL(_ text: String) -> Data? {
        var encoded = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        return Data(base64Encoded: encoded)
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
