import Foundation
import OSLog

private let claudeLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "claude-desktop-registration"
)

/// Detects a local Claude Desktop install and merges Curfew's MCP server
/// block into its `claude_desktop_config.json` with a single call.
///
/// The existing "Copy Config" button still works for every other MCP host
/// (Cursor, custom Electron apps, future MCP clients). Claude is the one
/// with a known config path and a stable JSON shape, so the one-click
/// path is worth the extra code — paste errors are a common first-run
/// failure mode.
///
/// Design notes:
///   - Never overwrite existing server blocks. If `mcpServers.curfew`
///     already exists and points at the same binary, surface the
///     `.alreadyRegistered` status so the UI can show a confirmation
///     badge rather than a write prompt.
///   - If `mcpServers.curfew` exists but points at a different binary
///     (e.g. the user moved the app), return `.willReplace` so the UI
///     can ask before overwriting.
///   - Atomic write with chmod 0600. Claude Desktop does not encrypt this
///     file; its contents include tool credentials for every registered
///     MCP server. World-readable would leak every user's full server list.
///   - Preserve unrelated JSON — keys we don't know about, comments
///     (dropped by JSON round-trip), and formatting. The app tries hard
///     to keep the user's other servers intact.
@MainActor
enum ClaudeDesktopRegistration {
    /// Result of a registration check or attempt.
    enum Status: Equatable {
        /// Claude Desktop isn't installed on this machine (config file absent).
        case claudeNotInstalled

        /// Curfew is already registered in the config at the current binary path.
        case alreadyRegistered

        /// Curfew is registered but at a different binary path — offer the user
        /// a replace option.
        case willReplace(existingCommand: String)

        /// Curfew is not registered. Call `register()` to add it.
        case notRegistered

        /// The write completed successfully.
        case registered
    }

    /// Canonical config path. Claude Desktop is macOS-only as of the MCP
    /// 2025-03-26 spec; no fallback search needed.
    static let configURL = URL(
        fileURLWithPath: NSHomeDirectory()
    )
    .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    .appendingPathComponent("claude_desktop_config.json")

    /// Path to the bundled `curfew-mcp` binary. Callers can inject a test
    /// path; the default resolves to `Curfew.app/Contents/Resources/curfew-mcp`.
    /// Marked `nonisolated` so it's usable as a default argument in
    /// MainActor-isolated members without triggering isolation errors.
    nonisolated static var bundledMCPBinary: String {
        Bundle.main.bundlePath + "/Contents/Resources/curfew-mcp"
    }

    /// Key under `mcpServers` for the running flavor. Production registers as
    /// `curfew`; a development build registers as `curfew-dev` so the two never
    /// clobber each other's entry in a shared Claude Desktop config.
    static var serverKey: String {
        switch CurfewFlavor.current {
        case .production: "curfew"
        case .development: "curfew-dev"
        }
    }

    /// Non-mutating status probe. Use this to drive UI state without
    /// touching the file.
    static func currentStatus(
        binary: String = bundledMCPBinary,
        fileManager: FileManager = .default
    ) -> Status {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return .claudeNotInstalled
        }
        guard let payload = readConfig() else {
            return .notRegistered
        }

        let servers = payload["mcpServers"] as? [String: Any] ?? [:]
        guard let curfew = servers[serverKey] as? [String: Any] else {
            return .notRegistered
        }
        let existingCommand = curfew["command"] as? String ?? ""
        if existingCommand == binary {
            return .alreadyRegistered
        }
        return .willReplace(existingCommand: existingCommand)
    }

    /// Writes the Curfew server block into Claude Desktop's config file.
    /// Returns `.registered` on success, or the appropriate
    /// `.claudeNotInstalled` / `.alreadyRegistered` value when no write
    /// was needed. Overwrites an existing `mcpServers.curfew` entry —
    /// callers should gate this on user confirmation when
    /// `currentStatus()` returned `.willReplace`.
    @discardableResult
    static func register(
        binary: String = bundledMCPBinary,
        fileManager: FileManager = .default
    ) throws -> Status {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return .claudeNotInstalled
        }

        var payload = readConfig() ?? [:]
        var servers = payload["mcpServers"] as? [String: Any] ?? [:]

        if let existing = servers[serverKey] as? [String: Any],
           existing["command"] as? String == binary {
            return .alreadyRegistered
        }

        var block: [String: Any] = [
            "command": binary,
            "args": [String]()
        ]
        // A development build tells the spawned curfew-mcp which flavor it
        // serves so the helper resolves the dev data paths rather than the
        // production install's. Production omits the key, leaving its
        // registration byte-identical to prior versions.
        if CurfewFlavor.current != .production {
            block["env"] = ["CURFEW_FLAVOR": CurfewFlavor.current.environmentValue]
        }
        servers[serverKey] = block
        payload["mcpServers"] = servers

        try writeConfig(payload)
        claudeLogger.info("Registered \(serverKey) (curfew-mcp) in Claude Desktop config")
        return .registered
    }

    // MARK: - Private

    /// Reads the config file as a top-level object. Returns nil if the
    /// file is missing or isn't a JSON object — the caller decides how
    /// to recover.
    private static func readConfig() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    /// Writes the payload atomically and restricts permissions to 0600.
    /// Claude Desktop's config contains OAuth tokens for other MCP
    /// servers — world-readable would leak credentials. 0600 matches
    /// what the app does for its own MCP request queue.
    private static func writeConfig(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: configURL.path
        )
    }
}
