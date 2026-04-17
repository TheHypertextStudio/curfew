import Foundation

/// Canonical filesystem paths shared by the Curfew app, `curfew-ctl`, and
/// `curfew-mcp`.
///
/// Keeping paths in one place prevents the three processes from disagreeing
/// about where settings, the activity log, or MCP request queues live.
/// All three processes must read from / write to the same files; any
/// divergence here silently produces stale reads.
public enum SharedPaths {
    /// `~/Library/Application Support/Curfew/`
    ///
    /// The Curfew app creates this directory on first launch. CLI/MCP tools
    /// assume it exists and fail gracefully when it doesn't (no app run yet).
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Curfew", isDirectory: true)
    }

    /// SQLite database file written by the app's `ActivityStore`.
    /// `curfew-ctl` and `curfew-mcp` open this read-only to serve activity
    /// queries without risking concurrent write corruption.
    public static var activityDatabase: URL {
        applicationSupport.appendingPathComponent("activity.sqlite3")
    }

    /// JSON queue file for pending MCP write-tool requests.
    ///
    /// `curfew-mcp` appends new `MCPPendingRequest` entries here.
    /// The Curfew app monitors this file via `MCPRequestMonitor` and
    /// surfaces a consent sheet for each pending entry. After the user
    /// approves or denies, the app updates the entry's `status` in-place.
    /// `curfew-mcp` polls this file to resolve the response it returns to
    /// the MCP client.
    public static var mcpRequestQueue: URL {
        applicationSupport.appendingPathComponent("mcp-requests.json")
    }

    /// User Defaults suite name used by the Curfew app (= its bundle ID).
    /// CLI/MCP tools pass this to `UserDefaults(suiteName:)` to read the
    /// same preferences plist the app writes via `UserDefaults.standard`.
    public static let defaultsSuiteName = "studio.hypertext.curfew"

    // MARK: - Privileged daemon paths (root-readable, user-writable via App Group)

    /// `/Library/Application Support/Curfew/` — written by the app, read by
    /// the privileged daemon. The app writes a sentinel file here when lockout
    /// starts; the daemon uses `KeepAlive.PathState` to watch the sentinel so
    /// it wakes up when the file appears and exits cleanly when it disappears.
    public static var privilegedApplicationSupport: URL {
        URL(fileURLWithPath: "/Library/Application Support/Curfew", isDirectory: true)
    }

    /// Sentinel file that signals an active lockout to the privileged daemon.
    /// The app creates this file on `working → locked` transition and deletes
    /// it on `locked → working/dayOff`. The daemon wakes on file creation and
    /// exits on deletion (via `KeepAlive.PathState`).
    public static var lockoutActiveSentinel: URL {
        privilegedApplicationSupport.appendingPathComponent("lockout-active")
    }
}
