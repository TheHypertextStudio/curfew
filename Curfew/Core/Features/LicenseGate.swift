import Combine
import CryptoKit
import Foundation

/// Base64-encoded 32-byte Ed25519 public key.
/// Replace this constant with the output of `scripts/gen-license-keypair.sh`
/// before shipping. The private half lives in `scripts/issue-license.ts` and
/// is never bundled with the app.
private let licensePublicKeyBase64 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

enum LicenseActivationError: LocalizedError {
    case malformed
    case invalidSignature
    case wrongProduct

    var errorDescription: String? {
        switch self {
        case .malformed: "The license key format is invalid."
        case .invalidSignature: "This license key could not be verified."
        case .wrongProduct: "This license key is for a different product."
        }
    }
}

/// Verifies and stores a Curfew Pro license key.
///
/// License key format: `{base64url(payloadJSON)}.{base64url(ed25519Signature)}`
/// The payload is a JSON object matching `LicenseKey`; the signature covers the
/// exact UTF-8 bytes of that JSON. Verification uses the Ed25519 public key
/// embedded above — the matching private key signs keys server-side via the
/// Lemonsqueezy webhook Worker.
@MainActor
final class LicenseGate: ObservableObject {
    @Published private(set) var activatedKey: LicenseKey?
    @Published private(set) var activationError: String?

    var isProUnlocked: Bool {
        activatedKey != nil
    }

    private let defaults: UserDefaults
    private static let storageKey = "pro.licenseKey"

    nonisolated init(
        defaults: UserDefaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    ) {
        self.defaults = defaults
    }

    func loadStoredKey() {
        guard let stored = defaults.string(forKey: Self.storageKey) else { return }
        activatedKey = try? verified(stored)
    }

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

    func deactivate() {
        activatedKey = nil
        activationError = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Private

    private func verified(_ keyString: String) throws -> LicenseKey {
        let parts = keyString.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let payloadData = Data(base64URLEncoded: String(parts[0])),
              let signatureData = Data(base64URLEncoded: String(parts[1]))
        else { throw LicenseActivationError.malformed }

        guard
            let rawKey = Data(base64Encoded: licensePublicKeyBase64),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
            publicKey.isValidSignature(signatureData, for: payloadData)
        else { throw LicenseActivationError.invalidSignature }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let key = try? decoder.decode(LicenseKey.self, from: payloadData)
        else { throw LicenseActivationError.malformed }

        guard key.product == "curfew-pro"
        else { throw LicenseActivationError.wrongProduct }

        return key
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = normalized.count % 4
        if pad != 0 { normalized += String(repeating: "=", count: 4 - pad) }
        self.init(base64Encoded: normalized)
    }
}
