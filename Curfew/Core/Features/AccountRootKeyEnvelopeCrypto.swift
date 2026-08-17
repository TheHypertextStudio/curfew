import CryptoKit
import CurfewProtocols
import Foundation

enum AccountRootKeyEnvelopeCrypto {
    private struct KeySchedule {
        let encapsulatedKey: Data
        let key: Data
        let nonce: Data
    }

    static func seal(
        rootKey: Data,
        recipient: CurfewProtocols.AccountDeviceEnrollment,
        createdAt: Date,
        ephemeralPrivateKey: Data? = nil
    ) throws -> RootKeyEnvelope {
        guard rootKey.count == 32,
              recipient.encryptionPublicKeyJwk.crv == .p256,
              recipient.encryptionPublicKeyJwk.kty == .ec,
              let recipientPoint = x963(recipient.encryptionPublicKeyJwk)
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let schedule = try keySchedule(
            recipientPoint: recipientPoint,
            ephemeralPrivateKey: ephemeralPrivateKey
        )
        let createdAtValue = formatter.string(from: createdAt)
        let sealed = try AES.GCM.seal(
            rootKey,
            using: SymmetricKey(data: schedule.key),
            nonce: AES.GCM.Nonce(data: schedule.nonce),
            authenticating: aad(recipient: recipient, createdAt: createdAtValue)
        )
        return RootKeyEnvelope(
            aead: .aes256Gcm,
            ciphertext: base64URL(sealed.ciphertext + sealed.tag),
            createdAt: createdAtValue,
            encapsulatedKey: base64URL(schedule.encapsulatedKey),
            info: .curfewRootKeyEnvelopeV2,
            kdf: .hkdfSha256,
            kem: .dhkemP256HkdfSha256,
            keyEpoch: recipient.keyEpoch,
            recipientDeviceID: recipient.deviceID
        )
    }

    private static func keySchedule(
        recipientPoint: Data,
        ephemeralPrivateKey: Data?
    ) throws -> KeySchedule {
        let ephemeral = try ephemeralPrivateKey.map {
            try P256.KeyAgreement.PrivateKey(rawRepresentation: $0)
        } ?? P256.KeyAgreement.PrivateKey()
        let encapsulated = ephemeral.publicKey.x963Representation
        let recipientKey = try P256.KeyAgreement.PublicKey(x963Representation: recipientPoint)
        let sharedDH = try ephemeral.sharedSecretFromKeyAgreement(with: recipientKey)
            .withUnsafeBytes { Data($0) }
        let kemSuite = Data("KEM".utf8) + i2osp(0x10, length: 2)
        let hpkeSuite = Data("HPKE".utf8) + i2osp(0x10, length: 2) +
            i2osp(1, length: 2) + i2osp(2, length: 2)
        let eaePRK = labeledExtract(
            suite: kemSuite,
            salt: Data(),
            label: "eae_prk",
            inputKeyMaterial: sharedDH
        )
        let sharedSecret = labeledExpand(
            suite: kemSuite,
            pseudorandomKey: eaePRK,
            label: "shared_secret",
            info: encapsulated + recipientPoint,
            length: 32
        )
        let context = keyScheduleContext(suite: hpkeSuite)
        let secret = labeledExtract(
            suite: hpkeSuite,
            salt: sharedSecret,
            label: "secret",
            inputKeyMaterial: Data()
        )
        return KeySchedule(
            encapsulatedKey: encapsulated,
            key: labeledExpand(
                suite: hpkeSuite,
                pseudorandomKey: secret,
                label: "key",
                info: context,
                length: 32
            ),
            nonce: labeledExpand(
                suite: hpkeSuite,
                pseudorandomKey: secret,
                label: "base_nonce",
                info: context,
                length: 12
            )
        )
    }

    private static func keyScheduleContext(suite: Data) -> Data {
        let pskIDHash = labeledExtract(
            suite: suite,
            salt: Data(),
            label: "psk_id_hash",
            inputKeyMaterial: Data()
        )
        let infoHash = labeledExtract(
            suite: suite,
            salt: Data(),
            label: "info_hash",
            inputKeyMaterial: Data(RootKeyEnvelopeInfo.curfewRootKeyEnvelopeV2.rawValue.utf8)
        )
        return Data([0]) + pskIDHash + infoHash
    }

    private static func aad(
        recipient: CurfewProtocols.AccountDeviceEnrollment,
        createdAt: String
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "createdAt": createdAt,
                "keyEpoch": recipient.keyEpoch,
                "recipientDeviceId": recipient.deviceID
            ],
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func x963(_ key: CurfewProtocols.AccountPublicKeyJWK) -> Data? {
        guard let xCoordinate = decodeBase64URL(key.x),
              let yCoordinate = decodeBase64URL(key.y),
              xCoordinate.count == 32,
              yCoordinate.count == 32
        else { return nil }
        return Data([0x04]) + xCoordinate + yCoordinate
    }

    private static func labeledExtract(
        suite: Data,
        salt: Data,
        label: String,
        inputKeyMaterial: Data
    ) -> Data {
        hkdfExtract(
            salt: salt,
            inputKeyMaterial: Data("HPKE-v1".utf8) + suite + Data(label.utf8) + inputKeyMaterial
        )
    }

    private static func labeledExpand(
        suite: Data,
        pseudorandomKey: Data,
        label: String,
        info: Data,
        length: Int
    ) -> Data {
        hkdfExpand(
            pseudorandomKey: pseudorandomKey,
            info: i2osp(length, length: 2) + Data("HPKE-v1".utf8) + suite +
                Data(label.utf8) + info,
            length: length
        )
    }

    private static func hkdfExtract(salt: Data, inputKeyMaterial: Data) -> Data {
        let key = SymmetricKey(data: salt.isEmpty ? Data(repeating: 0, count: 32) : salt)
        return Data(HMAC<SHA256>.authenticationCode(for: inputKeyMaterial, using: key))
    }

    private static func hkdfExpand(
        pseudorandomKey: Data,
        info: Data,
        length: Int
    ) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < length {
            previous = Data(HMAC<SHA256>.authenticationCode(
                for: previous + info + Data([counter]),
                using: SymmetricKey(data: pseudorandomKey)
            ))
            output.append(previous)
            counter += 1
        }
        return output.prefix(length)
    }

    private static func i2osp(_ value: Int, length: Int) -> Data {
        Data((0 ..< length).map { index in
            UInt8((value >> (8 * (length - index - 1))) & 0xFF)
        })
    }

    private static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime]
        return value
    }()
}
