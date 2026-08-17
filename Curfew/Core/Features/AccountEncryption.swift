import CryptoKit
import CurfewProtocols
import Foundation
import Security

protocol AccountSecretStoring: AnyObject {
    func data(for account: String) throws -> Data?
    func save(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

enum AccountEncryptionError: Error, Equatable {
    case invalidKeyMaterial
    case keychain(OSStatus)
    case authenticationFailed
}

final class KeychainAccountSecretStore: AccountSecretStoring {
    private let service = "studio.hypertext.curfew.account-e2ee"

    func data(for account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AccountEncryptionError.keychain(status)
        }
        return data
    }

    func save(_ data: Data, for account: String) throws {
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable: false
        ]
        let update = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var insertion = identity
            attributes.forEach { insertion[$0.key] = $0.value }
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else { throw AccountEncryptionError.keychain(status) }
        } else if update != errSecSuccess {
            throw AccountEncryptionError.keychain(update)
        }
    }

    func delete(_ account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountEncryptionError.keychain(status)
        }
    }
}

struct AccountPublicKeyJWK: Codable, Equatable, Sendable {
    let kty = "EC"
    let crv = "P-256"
    let x: String
    let y: String

    private enum CodingKeys: String, CodingKey { case kty, crv, x, y }

    init(publicKey: P256.Signing.PublicKey) {
        let point = publicKey.x963Representation
        self.x = Self.base64URL(point[1 ..< 33])
        self.y = Self.base64URL(point[33 ..< 65])
    }

    init(agreementPublicKey: P256.KeyAgreement.PublicKey) {
        let point = agreementPublicKey.x963Representation
        self.x = Self.base64URL(point[1 ..< 33])
        self.y = Self.base64URL(point[33 ..< 65])
    }

    var signingPublicKey: P256.Signing.PublicKey? {
        try? P256.Signing.PublicKey(x963Representation: x963)
    }

    private var x963: Data {
        var result = Data([0x04])
        result.append(Self.decodeBase64URL(x) ?? Data())
        result.append(Self.decodeBase64URL(y) ?? Data())
        return result
    }

    fileprivate static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

struct AccountRecoveryEnvelope: Codable, Equatable, Sendable {
    let keyEpoch: Int
    let kdf: String
    let aead: String
    let info: String
    let salt: String
    let nonce: String
    let ciphertext: String
    let createdAt: Date
}

struct AccountEnrollmentBootstrap: Equatable, Sendable {
    let recoveryKey: String
    let recoveryEnvelope: AccountRecoveryEnvelope
    let encryptionPublicKey: AccountPublicKeyJWK
    let signingPublicKey: AccountPublicKeyJWK
}

struct AccountDeviceKeyMaterial: Codable, Equatable, Sendable {
    let accountRootKey: Data
    let signingPrivateKey: Data
    let encryptionPrivateKey: Data

    var signingPublicKey: AccountPublicKeyJWK {
        AccountPublicKeyJWK(publicKey: try! P256.Signing.PrivateKey(
            rawRepresentation: signingPrivateKey
        ).publicKey)
    }
}

final class AccountDeviceKeyStore {
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring = KeychainAccountSecretStore()) {
        self.secretStore = secretStore
    }

    func createEnrollment(
        deviceID: UUID,
        keyEpoch: Int,
        createdAt: Date
    ) throws -> AccountEnrollmentBootstrap {
        guard keyEpoch > 0 else { throw AccountEncryptionError.invalidKeyMaterial }
        let rootKey = randomData(count: 32)
        let recoveryKeyData = randomData(count: 32)
        let signing = P256.Signing.PrivateKey()
        let encryption = P256.KeyAgreement.PrivateKey()
        let material = AccountDeviceKeyMaterial(
            accountRootKey: rootKey,
            signingPrivateKey: signing.rawRepresentation,
            encryptionPrivateKey: encryption.rawRepresentation
        )
        try secretStore.save(
            JSONEncoder.curfew.encode(material),
            for: accountName(deviceID)
        )
        let recoveryKey = AccountPublicKeyJWK.base64URL(recoveryKeyData)
        return try AccountEnrollmentBootstrap(
            recoveryKey: recoveryKey,
            recoveryEnvelope: AccountRecoveryCrypto.wrap(
                rootKey,
                recoveryKey: recoveryKey,
                keyEpoch: keyEpoch,
                createdAt: createdAt
            ),
            encryptionPublicKey: AccountPublicKeyJWK(
                agreementPublicKey: encryption.publicKey
            ),
            signingPublicKey: AccountPublicKeyJWK(publicKey: signing.publicKey)
        )
    }

    func load(deviceID: UUID) throws -> AccountDeviceKeyMaterial? {
        guard let data = try secretStore.data(for: accountName(deviceID)) else { return nil }
        return try JSONDecoder.curfew.decode(AccountDeviceKeyMaterial.self, from: data)
    }

    func replaceAccountRootKey(_ rootKey: Data, deviceID: UUID) throws {
        guard rootKey.count == 32,
              let existing = try load(deviceID: deviceID)
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let recovered = AccountDeviceKeyMaterial(
            accountRootKey: rootKey,
            signingPrivateKey: existing.signingPrivateKey,
            encryptionPrivateKey: existing.encryptionPrivateKey
        )
        try secretStore.save(
            JSONEncoder.curfew.encode(recovered),
            for: accountName(deviceID)
        )
    }

    private func accountName(_ deviceID: UUID) -> String {
        "device-\(deviceID.uuidString.lowercased())"
    }
}

enum AccountRecoveryCrypto {
    static func wrap(
        _ accountRootKey: Data,
        recoveryKey: String,
        keyEpoch: Int,
        createdAt: Date
    ) throws -> AccountRecoveryEnvelope {
        guard accountRootKey.count == 32,
              let recovery = AccountPublicKeyJWK.decodeBase64URL(recoveryKey),
              recovery.count == 32
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let salt = randomData(count: 16)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: recovery),
            salt: salt,
            info: Data("curfew-recovery-wrap-v2".utf8),
            outputByteCount: 32
        )
        let nonce = AES.GCM.Nonce()
        let aad = try canonicalJSON(["createdAt": wireDate(createdAt), "keyEpoch": keyEpoch])
        let sealed = try AES.GCM.seal(accountRootKey, using: key, nonce: nonce, authenticating: aad)
        return AccountRecoveryEnvelope(
            keyEpoch: keyEpoch,
            kdf: "HKDF-SHA256",
            aead: "AES-256-GCM",
            info: "curfew-recovery-wrap-v2",
            salt: AccountPublicKeyJWK.base64URL(salt),
            nonce: AccountPublicKeyJWK.base64URL(Data(nonce)),
            ciphertext: AccountPublicKeyJWK.base64URL(sealed.ciphertext + sealed.tag),
            createdAt: createdAt
        )
    }

    static func unwrap(
        _ envelope: AccountRecoveryEnvelope,
        recoveryKey: String
    ) throws -> Data {
        guard envelope.kdf == "HKDF-SHA256",
              envelope.aead == "AES-256-GCM",
              envelope.info == "curfew-recovery-wrap-v2",
              let recovery = AccountPublicKeyJWK.decodeBase64URL(recoveryKey),
              let salt = AccountPublicKeyJWK.decodeBase64URL(envelope.salt),
              let nonceData = AccountPublicKeyJWK.decodeBase64URL(envelope.nonce),
              let combined = AccountPublicKeyJWK.decodeBase64URL(envelope.ciphertext),
              recovery.count == 32,
              salt.count == 16,
              nonceData.count == 12,
              combined.count == 48
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: recovery),
            salt: salt,
            info: Data(envelope.info.utf8),
            outputByteCount: 32
        )
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        let aad = try canonicalJSON([
            "createdAt": wireDate(envelope.createdAt),
            "keyEpoch": envelope.keyEpoch
        ])
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }
}

enum AccountRecoveryEnvelopeBridge {
    static func generated(_ envelope: AccountRecoveryEnvelope) -> RecoveryKeyEnvelope {
        RecoveryKeyEnvelope(
            aead: .aes256Gcm,
            ciphertext: envelope.ciphertext,
            createdAt: wireDate(envelope.createdAt),
            info: .curfewRecoveryWrapV2,
            kdf: .hkdfSha256,
            keyEpoch: envelope.keyEpoch,
            nonce: envelope.nonce,
            salt: envelope.salt
        )
    }

    static func local(_ envelope: RecoveryKeyEnvelope) throws -> AccountRecoveryEnvelope {
        guard envelope.aead == .aes256Gcm,
              envelope.info == .curfewRecoveryWrapV2,
              envelope.kdf == .hkdfSha256,
              let createdAt = ISO8601DateFormatter.curfew.date(from: envelope.createdAt)
        else { throw AccountEncryptionError.invalidKeyMaterial }
        return AccountRecoveryEnvelope(
            keyEpoch: envelope.keyEpoch,
            kdf: envelope.kdf.rawValue,
            aead: envelope.aead.rawValue,
            info: envelope.info.rawValue,
            salt: envelope.salt,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
            createdAt: createdAt
        )
    }
}

enum AccountEncryptedRecordNamespace: String, Codable, Sendable {
    case accountSettings = "account_settings"
    case wakePolicy = "wake_policy"
    case callbacks
    case campaigns
}

struct AccountEncryptedRecord: Codable, Equatable, Sendable {
    let namespace: AccountEncryptedRecordNamespace
    let recordID: UUID
    let version: Int
    let writerDeviceID: UUID
    let writerCounter: Int
    let keyEpoch: Int
    let cipherSuite: String
    let nonce: String
    let aadDigest: String
    let ciphertext: String
    let signatureAlgorithm: String
    let signature: String
    let updatedAt: Date

    func replacing(ciphertext: String) -> AccountEncryptedRecord {
        AccountEncryptedRecord(
            namespace: namespace,
            recordID: recordID,
            version: version,
            writerDeviceID: writerDeviceID,
            writerCounter: writerCounter,
            keyEpoch: keyEpoch,
            cipherSuite: cipherSuite,
            nonce: nonce,
            aadDigest: aadDigest,
            ciphertext: ciphertext,
            signatureAlgorithm: signatureAlgorithm,
            signature: signature,
            updatedAt: updatedAt
        )
    }
}

struct AccountRecordCrypto {
    func seal(
        _ value: some Encodable,
        namespace: AccountEncryptedRecordNamespace,
        recordID: UUID,
        version: Int,
        writerCounter: Int,
        writerDeviceID: UUID,
        keyEpoch: Int,
        updatedAt: Date,
        keys: AccountDeviceKeyMaterial
    ) throws -> AccountEncryptedRecord {
        guard keys.accountRootKey.count == 32,
              version > 0, writerCounter > 0, keyEpoch > 0
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let header = headerObject(
            namespace: namespace,
            recordID: recordID,
            version: version,
            writerCounter: writerCounter,
            writerDeviceID: writerDeviceID,
            keyEpoch: keyEpoch,
            updatedAt: updatedAt
        )
        let aad = try canonicalJSON(header)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            JSONEncoder.curfew.encode(value),
            using: namespaceKey(keys.accountRootKey, namespace, keyEpoch),
            nonce: nonce,
            authenticating: aad
        )
        let ciphertext = AccountPublicKeyJWK.base64URL(sealed.ciphertext + sealed.tag)
        let aadDigest = AccountPublicKeyJWK.base64URL(Data(SHA256.hash(data: aad)))
        let unsigned = AccountEncryptedRecord(
            namespace: namespace,
            recordID: recordID,
            version: version,
            writerDeviceID: writerDeviceID,
            writerCounter: writerCounter,
            keyEpoch: keyEpoch,
            cipherSuite: "AES-256-GCM",
            nonce: AccountPublicKeyJWK.base64URL(Data(nonce)),
            aadDigest: aadDigest,
            ciphertext: ciphertext,
            signatureAlgorithm: "ES256-P1363-SHA256",
            signature: "",
            updatedAt: updatedAt
        )
        let signingKey = try P256.Signing.PrivateKey(rawRepresentation: keys.signingPrivateKey)
        let signature = try signingKey.signature(for: signatureInput(unsigned)).rawRepresentation
        return AccountEncryptedRecord(
            namespace: unsigned.namespace,
            recordID: unsigned.recordID,
            version: unsigned.version,
            writerDeviceID: unsigned.writerDeviceID,
            writerCounter: unsigned.writerCounter,
            keyEpoch: unsigned.keyEpoch,
            cipherSuite: unsigned.cipherSuite,
            nonce: unsigned.nonce,
            aadDigest: unsigned.aadDigest,
            ciphertext: unsigned.ciphertext,
            signatureAlgorithm: unsigned.signatureAlgorithm,
            signature: AccountPublicKeyJWK.base64URL(signature),
            updatedAt: unsigned.updatedAt
        )
    }

    func open<Value: Decodable>(
        _ record: AccountEncryptedRecord,
        as type: Value.Type,
        accountRootKey: Data,
        signingPublicKey: AccountPublicKeyJWK
    ) throws -> Value {
        guard record.cipherSuite == "AES-256-GCM",
              record.signatureAlgorithm == "ES256-P1363-SHA256",
              let publicKey = signingPublicKey.signingPublicKey,
              let signatureData = AccountPublicKeyJWK.decodeBase64URL(record.signature),
              let nonceData = AccountPublicKeyJWK.decodeBase64URL(record.nonce),
              let combined = AccountPublicKeyJWK.decodeBase64URL(record.ciphertext),
              signatureData.count == 64,
              nonceData.count == 12,
              combined.count >= 16
        else { throw AccountEncryptionError.invalidKeyMaterial }
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        guard try publicKey.isValidSignature(signature, for: signatureInput(record)) else {
            throw AccountEncryptionError.authenticationFailed
        }
        let aad = try canonicalJSON(headerObject(
            namespace: record.namespace,
            recordID: record.recordID,
            version: record.version,
            writerCounter: record.writerCounter,
            writerDeviceID: record.writerDeviceID,
            keyEpoch: record.keyEpoch,
            updatedAt: record.updatedAt
        ))
        guard AccountPublicKeyJWK.base64URL(Data(SHA256.hash(data: aad))) == record.aadDigest else {
            throw AccountEncryptionError.authenticationFailed
        }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        let plaintext = try AES.GCM.open(
            box,
            using: namespaceKey(accountRootKey, record.namespace, record.keyEpoch),
            authenticating: aad
        )
        return try JSONDecoder.curfew.decode(type, from: plaintext)
    }

    private func signatureInput(_ record: AccountEncryptedRecord) throws -> Data {
        try canonicalJSON([
            "aadDigest": record.aadDigest,
            "cipherSuite": record.cipherSuite,
            "ciphertext": record.ciphertext,
            "keyEpoch": record.keyEpoch,
            "namespace": record.namespace.rawValue,
            "nonce": record.nonce,
            "recordId": record.recordID.uuidString.lowercased(),
            "signatureAlgorithm": record.signatureAlgorithm,
            "updatedAt": wireDate(record.updatedAt),
            "version": record.version,
            "writerCounter": record.writerCounter,
            "writerDeviceId": record.writerDeviceID.uuidString.lowercased()
        ])
    }
}

private func namespaceKey(
    _ accountRootKey: Data,
    _ namespace: AccountEncryptedRecordNamespace,
    _ keyEpoch: Int
) -> SymmetricKey {
    HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: accountRootKey),
        salt: Data("curfew-encrypted-record-v2".utf8),
        info: Data("namespace=\(namespace.rawValue);keyEpoch=\(keyEpoch)".utf8),
        outputByteCount: 32
    )
}

private func headerObject(
    namespace: AccountEncryptedRecordNamespace,
    recordID: UUID,
    version: Int,
    writerCounter: Int,
    writerDeviceID: UUID,
    keyEpoch: Int,
    updatedAt: Date
) -> [String: Any] {
    [
        "cipherSuite": "AES-256-GCM",
        "keyEpoch": keyEpoch,
        "namespace": namespace.rawValue,
        "recordId": recordID.uuidString.lowercased(),
        "updatedAt": wireDate(updatedAt),
        "version": version,
        "writerCounter": writerCounter,
        "writerDeviceId": writerDeviceID.uuidString.lowercased()
    ]
}

private func canonicalJSON(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

private func wireDate(_ date: Date) -> String {
    ISO8601DateFormatter.curfew.string(from: date)
}

private func randomData(count: Int) -> Data {
    var bytes = Data(count: count)
    bytes.withUnsafeMutableBytes { pointer in
        precondition(SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!) ==
            errSecSuccess)
    }
    return bytes
}

private extension JSONEncoder {
    static var curfew: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var curfew: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let curfew: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
