import Foundation
import LocalAuthentication
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

nonisolated enum BackgroundKeychainQuery {
    static func identity(service: String, account: String) -> [CFString: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationContext: context
        ]
    }

    static func read(service: String, account: String) -> [CFString: Any] {
        var query = identity(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        return query
    }
}

final nonisolated class KeychainAccountSecretStore: AccountSecretStoring {
    private let service: String

    init(service: String = CurfewServiceEndpoints.current.keychainService) {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        let query = Self.backgroundReadQuery(service: service, account: account)
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

    static func backgroundReadQuery(service: String, account: String) -> [CFString: Any] {
        BackgroundKeychainQuery.read(service: service, account: account)
    }

    func save(_ data: Data, for account: String) throws {
        let identity = BackgroundKeychainQuery.identity(service: service, account: account)
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
        let query = BackgroundKeychainQuery.identity(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountEncryptionError.keychain(status)
        }
    }
}
