import Foundation

/// The persisted user-controlled boundary for the standalone local MCP server.
///
/// `curfew-mcp` is launched by an external host such as Claude Desktop, so
/// stopping Curfew's in-app request monitor is not sufficient to revoke access.
/// The server checks this policy again for every tool-list and tool-call request.
public enum LocalMCPAccessPolicy {
    /// Reads the switch from an injected store so app tests can use an isolated
    /// defaults suite without touching the developer's real Curfew settings.
    public static func isEnabled(in settingsStore: CurfewSettingsStore) -> Bool {
        settingsStore.load().mcpEnabled
    }

    /// Reads the same flavor-specific defaults suite used by the Curfew app.
    public static func isEnabledInSharedSettings() -> Bool {
        let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
        return isEnabled(in: CurfewSettingsStore(defaults: defaults))
    }
}
