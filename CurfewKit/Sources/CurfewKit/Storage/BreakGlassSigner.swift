import CryptoKit
import Foundation
import OSLog

private let breakGlassSignerLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "break-glass"
)

/// Signs and verifies ``BreakGlassRelease`` records with a per-install
/// symmetric key, mirroring ``MCPRequestSigner`` so there is one signing
/// pattern in the codebase rather than two.
public enum BreakGlassSigner {
    /// Hex-encoded HMAC-SHA256 of `{id}|{issuedAt-ISO}|{reason}|{issuedBy}`,
    /// or `nil` when the key is unavailable.
    public static func sign(
        _ release: BreakGlassRelease,
        secretURL: URL = SharedPaths.breakGlassSecret
    ) -> String? {
        guard let key = loadOrCreateSecret(at: secretURL),
              let data = canonicalString(for: release).data(using: .utf8)
        else {
            return nil
        }
        return HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Whether `release.signature` matches the canonical payload. Missing
    /// signature, missing key, and mismatch all return `false` — the call
    /// sites treat them identically (do not stand enforcement down).
    public static func verify(
        _ release: BreakGlassRelease,
        secretURL: URL = SharedPaths.breakGlassSecret
    ) -> Bool {
        guard let signature = release.signature,
              let key = try? readSecret(at: secretURL),
              let signatureData = Data(breakGlassHex: signature),
              let payload = canonicalString(for: release).data(using: .utf8)
        else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: payload,
            using: key
        )
    }

    /// Wire contract for the signature. Order and separators are load-bearing:
    /// changing either invalidates every record already on disk.
    private static func canonicalString(for release: BreakGlassRelease) -> String {
        let timestamp = ISO8601DateFormatter.curfewBreakGlass.string(from: release.issuedAt)
        var fields = [
            release.id.uuidString,
            timestamp,
            release.reason,
            release.issuedBy
        ]
        if let expiresAt = release.expiresAt {
            fields.append(ISO8601DateFormatter.curfewBreakGlass.string(from: expiresAt))
        }
        return fields.joined(separator: "|")
    }

    private static func loadOrCreateSecret(at url: URL) -> SymmetricKey? {
        do {
            if let existing = try readSecret(at: url) {
                return existing
            }
            let generated = SymmetricKey(size: .bits256)
            let data = generated.withUnsafeBytes { Data($0) }
            if try BreakGlassPrivateFileWriter.write(data, to: url, replaceExisting: false) {
                return generated
            }
            return try readSecret(at: url)
        } catch {
            breakGlassSignerLogger.error(
                "failed to read or provision break-glass secret: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func readSecret(at url: URL) throws -> SymmetricKey? {
        guard let data = try BoundedRegularFileReader.read(url, maximumBytes: 32)
        else { return nil }
        guard data.count == 32 else { throw CocoaError(.coderReadCorrupt) }
        return SymmetricKey(data: data)
    }
}

// MARK: - Private helpers

private extension ISO8601DateFormatter {
    /// Single formatter reused across sign and verify so the wire string is
    /// stable. Fractional seconds are excluded on purpose — they would not
    /// survive the JSON round-trip identically.
    static let curfewBreakGlass: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension Data {
    /// Parses a hex string into bytes, failing closed on any non-hex input.
    init?(breakGlassHex string: String) {
        let cleaned = string.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(after: index)
            guard let byte = UInt8(String(cleaned[index ... next]), radix: 16) else { return nil }
            bytes.append(byte)
            index = cleaned.index(after: next)
        }
        self.init(bytes)
    }
}
