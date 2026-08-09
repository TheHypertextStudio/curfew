import Foundation
import OSLog
import Security

/// Where the coordinator's shared signing secret lives.
///
/// A protocol so the suite can drive the whole reporting path without touching
/// the login keychain — no test run should be able to write a credential onto
/// the machine running it, or to fail because that machine's keychain is
/// locked over SSH.
///
/// The unset state is the empty string rather than `nil`. That is the same
/// spelling ``DeviceStatusReportingPolicy`` uses for an unset address, and it
/// keeps the one question callers ask — "may I sign?" — a single
/// `isEmpty` check rather than an optional dance at every call site.
protocol DeviceAssertionSecretStoring: AnyObject {
    /// The stored secret, or `""` when there is none.
    var secret: String { get }

    /// Stores `secret`, or removes it when `secret` is empty. Returns whether
    /// the store now holds what was asked of it.
    @discardableResult
    func store(_ secret: String) -> Bool
}

/// The production store: one generic-password item in the user's keychain.
///
/// **Why the Keychain and not `UserDefaults`.** Everything else in
/// ``DeviceStatusReportingPolicy`` — the address, the cadence, the device
/// identifier — is configuration, and lives in the settings plist with the rest
/// of it. This is not configuration. It is the credential that authenticates
/// every status report, held by the coordinator and every device on the
/// account, and a plist is a file: readable by anything running as this user,
/// copied verbatim into Time Machine and any backup, synced by whatever syncs a
/// home directory, and printed in full by anyone who runs `defaults read` while
/// debugging something else. The keychain is the one place on macOS where a
/// secret is encrypted at rest under the login password, excluded from ordinary
/// backups, and gated per-application by the OS. A shared secret that leaks
/// authenticates *every* device on the account, which is exactly the blast
/// radius that argues for the stronger store.
///
/// **Which keychain.** The file-based login keychain, i.e. the default when
/// `kSecUseDataProtectionKeychain` is not set. Curfew is deliberately not
/// sandboxed (see `Curfew.entitlements`) and carries no
/// `keychain-access-groups`; the data-protection keychain would require one and
/// would make an ad-hoc-signed local build unable to read its own secret.
final class KeychainDeviceAssertionSecretStore: DeviceAssertionSecretStoring {
    /// The process-wide store. A single instance because the underlying item is
    /// process-wide too, and because the Settings panel and the reporter must
    /// agree about what is stored the moment it changes.
    static let shared = KeychainDeviceAssertionSecretStore()

    /// `kSecAttrService` — Curfew's bundle identifier, suffixed so a future
    /// second credential gets its own item rather than overwriting this one.
    static let service = "studio.hypertext.curfew.coordinator"

    /// `kSecAttrAccount`. Names what the item is, not who owns it: there is one
    /// coordinator secret per install.
    static let account = "device-assertion-secret"

    private let logger = Logger(subsystem: "studio.hypertext.curfew", category: "sync")

    var secret: String {
        var query = Self.baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            // `errSecItemNotFound` is the ordinary unconfigured state and is not
            // worth a log line. Anything else is a locked or broken keychain,
            // and the caller's response is the same either way: do not sign.
            if status != errSecItemNotFound {
                logger.error("Could not read the coordinator secret: \(status, privacy: .public)")
            }
            return ""
        }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
            return ""
        }
        return secret
    }

    @discardableResult
    func store(_ secret: String) -> Bool {
        guard !secret.isEmpty else { return clear() }

        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        let updated = SecItemUpdate(Self.baseQuery as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess {
            return true
        }

        var insert = Self.baseQuery
        insert[kSecValueData as String] = Data(secret.utf8)
        // Available whenever the user is logged in, which is whenever Curfew is
        // running. Not `...ThisDeviceOnly`'s synchronisable counterpart: this
        // secret must not ride iCloud Keychain to devices the user never
        // enrolled.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else {
            logger.error("Could not store the coordinator secret: \(added, privacy: .public)")
            return false
        }
        return true
    }

    /// Removes the item. Treats "there was nothing there" as success, because
    /// the caller asked for an empty store and an empty store is what it gets.
    @discardableResult
    private func clear() -> Bool {
        let status = SecItemDelete(Self.baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// The item's identity, shared by every operation so a typo cannot make the
    /// reader and the writer disagree about which item they mean.
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// A store that keeps the secret in memory and nowhere else.
///
/// The suite's default, and the reason no test run writes to a keychain. Also
/// what a preview gets, so a SwiftUI canvas cannot prompt for keychain access.
final class InMemoryDeviceAssertionSecretStore: DeviceAssertionSecretStoring {
    private(set) var secret: String

    init(secret: String = "") {
        self.secret = secret
    }

    @discardableResult
    func store(_ secret: String) -> Bool {
        self.secret = secret
        return true
    }
}
