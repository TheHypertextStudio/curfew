import Combine
import CryptoKit
import CurfewKit
import Foundation

/// Sentinel value for the unconfigured placeholder public key. Kept as its
/// own constant so `LicenseGate.verified` can fail-closed when the build has
/// not yet been pointed at a real signing key, and so CI can grep for the
/// literal to reject release tags that still carry it.
private let placeholderPublicKeyBase64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

/// Failure modes for Pro-license activation. Every case maps to a
/// human-readable `errorDescription` consumed by `LicenseView` when
/// surfacing the failure to the user.
enum LicenseActivationError: LocalizedError {
    /// The key string didn't split into a valid `{payload}.{signature}`
    /// base64url pair, or the embedded JSON payload failed to decode.
    case malformed
    /// Ed25519 signature verification failed against the embedded
    /// public key. Either the key is forged or this build is
    /// mismatched against the signer.
    case invalidSignature
    /// Signature is valid but the payload's `product` field names a
    /// different Curfew SKU — e.g. a Team licence presented to a Pro build.
    case wrongProduct
    /// The app was built with the placeholder public key still in place.
    /// License verification is skipped rather than accepting a key that
    /// could be forged against the all-zero key.
    case publicKeyNotProvisioned

    /// Localizable error copy surfaced to the user.
    var errorDescription: String? {
        switch self {
        case .malformed: "The license key format is invalid."
        case .invalidSignature: "This license key could not be verified."
        case .wrongProduct: "This license key is for a different product."
        case .publicKeyNotProvisioned:
            "This build does not have a license public key configured. " +
                "Pro activation is disabled until the developer ships a signed build."
        }
    }
}

/// Verifies and stores a Curfew Pro license key.
///
/// License key format: `{base64url(payloadJSON)}.{base64url(ed25519Signature)}`
/// The payload is a JSON object matching `LicenseKey`; the signature covers the
/// exact UTF-8 bytes of that JSON. Verification uses the Ed25519 public key
/// embedded above — the matching private key signs keys server-side via the
/// license issuer Worker secret `LICENSE_PRIVATE_KEY`.
@MainActor
final class LicenseGate: ObservableObject {
    /// Standard-base64 Ed25519 public key for the current Curfew Plus issuer.
    /// The matching private seed is an external Worker secret and is never
    /// bundled, committed, logged, or read by the app.
    static let configuredPublicKeyBase64 = "UKRq5y4Zyahv2VxzLfx4Gth8uTJLvqiIESpJ+dkER+4="

    /// Verified Pro license currently in effect, or `nil` for free-tier
    /// users. Setting surfaces Pro features across the app through the
    /// `isProUnlocked` derived boolean.
    @Published private(set) var activatedKey: LicenseKey?
    /// Localized error string from the most recent failed `activate(_:)`
    /// call, or `nil` after a successful activation / fresh launch.
    @Published private(set) var activationError: String?

    /// Convenience: `true` when a verified licence is stored. The whole
    /// Pro gate flows through this one flag so the rest of the code
    /// never touches the crypto types.
    var isProUnlocked: Bool {
        isPlusUnlocked
    }

    /// Plus is active for lifetime keys and only until expiry for subscriptions.
    var isPlusUnlocked: Bool {
        guard let key = activatedKey else { return false }
        return key.plan == .lifetime || (key.expiresAt ?? .distantPast) > Date()
    }

    private let defaults: UserDefaults
    private static let storageKey = "pro.licenseKey"

    /// Creates a gate backed by `defaults`. `nonisolated` so it can be
    /// evaluated as a default-parameter value in MainActor initializers.
    nonisolated init(
        defaults: UserDefaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    ) {
        self.defaults = defaults
    }

    /// Re-verifies any persisted licence string on app launch. Failures
    /// are silent — a malformed stored key simply leaves `activatedKey`
    /// nil so the user re-enters when visiting Settings → License.
    func loadStoredKey() {
        guard let stored = defaults.string(forKey: Self.storageKey) else { return }
        activatedKey = try? verified(stored)
    }

    /// Re-runs verification against the persisted licence so a UserDefaults
    /// tamper or a clock-rollback can't keep Pro alive indefinitely. Called
    /// from the model tick loop on a daily cadence (see
    /// ``CurfewAppModel.reverifyLicenseIfDue``). Safe to call at any time;
    /// flips `activatedKey` to `nil` when re-verification fails. License
    /// verification is purely offline (Ed25519 signature against the
    /// embedded public key), so this is cheap and fail-closed.
    func reverifyStoredKey() {
        guard let stored = defaults.string(forKey: Self.storageKey) else {
            if activatedKey != nil {
                activatedKey = nil
            }
            return
        }
        let next = try? verified(stored)
        if next != activatedKey {
            activatedKey = next
        }
    }

    /// Verifies and (on success) persists the given licence string.
    /// Failure surfaces via `activationError` for the UI to display.
    func activate(_ keyString: String) {
        activationError = nil
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            activatedKey = try verified(trimmed)
            defaults.set(trimmed, forKey: Self.storageKey)
        } catch {
            activationError = error.localizedDescription
        }
    }

    /// Clears the in-memory licence and removes the persisted string.
    /// Pro features immediately lock down via the `isProUnlocked` flip.
    func deactivate() {
        activatedKey = nil
        activationError = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    #if DEBUG
        /// Debug-only hook for exercising `isProUnlocked` without a real
        /// signed key. Used by `LifecycleWiringTests` to assert that
        /// downstream engines react to activation. Not compiled into
        /// Release builds, so production verification stays cryptographic.
        func testInjectActivatedKey(_ key: LicenseKey?) {
            activatedKey = key
        }
    #endif

    // MARK: - Private

    private func verified(_ keyString: String) throws -> LicenseKey {
        // Fail-closed when the build still carries the placeholder zero key.
        // Without this guard an attacker who discovered the all-zero private
        // key (trivially derivable) could forge arbitrary licenses.
        guard Self.configuredPublicKeyBase64 != placeholderPublicKeyBase64
        else { throw LicenseActivationError.publicKeyNotProvisioned }

        let parts = keyString.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let payloadData = Data(base64URLEncoded: String(parts[0])),
              let signatureData = Data(base64URLEncoded: String(parts[1]))
        else { throw LicenseActivationError.malformed }

        guard
            let rawKey = Data(base64Encoded: Self.configuredPublicKeyBase64),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
            publicKey.isValidSignature(signatureData, for: payloadData)
        else { throw LicenseActivationError.invalidSignature }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let key = try? decoder.decode(LicenseKey.self, from: payloadData)
        else { throw LicenseActivationError.malformed }

        guard key.product == "curfew-plus" || (key.product == "curfew-pro" && key.plan == .lifetime)
        else { throw LicenseActivationError.wrongProduct }

        return key
    }
}

private extension Data {
    /// Decodes a base64url-encoded string (URL-safe alphabet, optional
    /// missing `=` padding). Used by `LicenseGate.verified` to split
    /// the two halves of the licence key format.
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = normalized.count % 4
        if pad != 0 {
            normalized += String(repeating: "=", count: 4 - pad)
        }
        self.init(base64Encoded: normalized)
    }
}
