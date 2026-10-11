import CryptoKit
import Foundation
import OSLog

private let mcpSignerLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "mcp-signer"
)

/// Per-install symmetric key used to sign MCP write-tool requests. The
/// app generates one on first use, stores it in the user's shared
/// support directory with 0600 permissions, and reads it on every
/// verification. `curfew-mcp` (running as the same user) reads the same
/// file to sign requests it appends to the queue.
///
/// Threat model: an attacker who can read this file already has the
/// user's shell privileges and can write the queue directly — so the
/// secret isn't a hard authentication boundary. What it *does* close is
/// the `aiConsentPolicy = .autoApprove` bypass surface: any unsigned or
/// forged request now refuses auto-approval and falls through to the
/// consent sheet, where a human catches the spoof.
public enum MCPRequestSigner {
    /// HMAC-SHA256 of `{id}|{tool}|{argumentsJSON}|{requestedAt-ISO}`
    /// hex-encoded. `nil` when the secret can't be read or HMAC
    /// computation fails — callers treat `nil` as "could not sign,"
    /// distinct from "did not sign."
    public static func sign(_ request: MCPPendingRequest) -> String? {
        guard let key = loadOrCreateSecret() else { return nil }
        let payload = canonicalString(for: request)
        guard let data = payload.data(using: .utf8) else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies `request.signature` against the canonical payload string
    /// using the same key. Returns `false` for missing signatures,
    /// missing keys, or any mismatch — all three are treated the same
    /// at the call site (do-not-auto-approve), so the boolean stays
    /// flat instead of carrying a reason.
    public static func verify(_ request: MCPPendingRequest) -> Bool {
        guard let signature = request.signature,
              let key = loadOrCreateSecret(),
              let signatureData = Data(hexEncoded: signature),
              let payload = canonicalString(for: request).data(using: .utf8)
        else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: payload,
            using: key
        )
    }

    /// Stable string built from the request fields a verifier must
    /// re-derive. Order and separators are part of the wire contract —
    /// changing either invalidates every queued signature, so any
    /// future schema bump should rename the function and version it.
    private static func canonicalString(for request: MCPPendingRequest) -> String {
        let timestamp = ISO8601DateFormatter.curfewMCP.string(from: request.requestedAt)
        return [
            request.id.uuidString,
            request.tool.rawValue,
            request.argumentsJSON,
            timestamp
        ].joined(separator: "|")
    }

    /// Reads the symmetric key from disk; creates one if absent. Stored
    /// at `SharedPaths.mcpSharedSecret` with mode `0600`. Failure to
    /// read/create returns `nil` — sign/verify both fall through to
    /// "could not sign," and the consent surface picks up the slack.
    private static func loadOrCreateSecret() -> SymmetricKey? {
        let url = SharedPaths.mcpSharedSecret
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let key = SymmetricKey(size: .bits256)
            let data = key.withUnsafeBytes { Data($0) }
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: url.path
            )
            mcpSignerLogger.info("generated new MCP shared secret")
            return key
        } catch {
            mcpSignerLogger.error(
                "failed to provision MCP secret: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

private extension ISO8601DateFormatter {
    /// Single formatter reused across sign/verify so the wire string
    /// stays stable across calls. Using `.withInternetDateTime` keeps
    /// it timezone-explicit and fractional-second-free for canonical
    /// comparison.
    static let curfewMCP: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension Data {
    /// Parses a hex-encoded string into raw bytes. Returns `nil` for any
    /// non-hex character or odd-length input so callers can fail closed.
    init?(hexEncoded string: String) {
        let cleaned = string.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(after: index)
            let pair = String(cleaned[index ... next])
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            bytes.append(byte)
            index = cleaned.index(after: next)
        }
        self.init(bytes)
    }
}
