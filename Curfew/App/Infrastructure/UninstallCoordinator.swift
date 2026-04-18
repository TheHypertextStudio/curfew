import AppKit
import Foundation
import OSLog

private let uninstallLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "uninstall"
)

/// Orchestrates a complete uninstall of Curfew's local state.
///
/// Removes the four places the app writes on disk:
///   1. `~/Library/Application Support/Curfew/` — activity SQLite, MCP queue,
///      Unix socket (if live), lockout sentinel staging directory.
///   2. `~/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist` — the
///      `PersistentLockdown` respawn agent (best-effort `launchctl unload`
///      first so the agent doesn't re-launch the app mid-uninstall).
///   3. `~/Library/Preferences/studio.hypertext.curfew.plist` — UserDefaults
///      domain holding schedule, budgets, license key, settings.
///   4. `~/Library/Caches/studio.hypertext.curfew/` — incidental cache files.
///
/// The app bundle itself lives in `/Applications/` and is user-managed — the
/// coordinator surfaces a drag-to-Trash prompt rather than deleting it
/// programmatically, which would require additional prompts and would break
/// self-relaunch in-progress if invoked from inside the bundle.
///
/// Errors are logged and collected into a human-readable summary so the UI
/// can tell the user which paths (if any) could not be cleaned — but the
/// happy path proceeds even when one step fails, because leaving *some*
/// state behind is less bad than leaving *all* of it.
@MainActor
enum UninstallCoordinator {
    /// Result of a full uninstall run.
    struct Outcome: Equatable {
        /// Paths that were successfully removed.
        let removed: [String]

        /// Paths that failed to remove, paired with the best-effort reason.
        let failed: [(path: String, reason: String)]

        /// `true` when every targeted path was removed.
        var allSucceeded: Bool {
            failed.isEmpty
        }

        /// Plain-text summary suitable for an alert body. Intentionally
        /// avoids disclosing any user data from inside the paths — only
        /// the path strings, which the user already sees in Finder.
        var summary: String {
            var lines: [String] = []
            if !removed.isEmpty {
                lines.append("Removed:")
                lines.append(contentsOf: removed.map { "  • \($0)" })
            }
            if !failed.isEmpty {
                lines.append("")
                lines.append("Could not remove:")
                lines.append(contentsOf: failed.map { "  • \($0.path) — \($0.reason)" })
            }
            return lines.joined(separator: "\n")
        }

        /// Equatable conformance. `failed` is compared by path only —
        /// the reason strings may vary by platform without meaning the
        /// outcomes differ.
        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.removed == rhs.removed
                && lhs.failed.map(\.path) == rhs.failed.map(\.path)
        }
    }

    /// Executes the full uninstall sequence synchronously on the main actor.
    /// Returns an `Outcome` describing every path touched.
    @discardableResult
    static func performUninstall(
        fileManager: FileManager = .default,
        home: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        )
    ) -> Outcome {
        var removed: [String] = []
        var failed: [(path: String, reason: String)] = []

        // 1. Unload the LaunchAgent before deleting its plist so launchd
        //    does not respawn the app between `rm` and `launchctl`. The
        //    failure mode here is benign — if the agent was never loaded,
        //    `launchctl unload` prints a warning and exits non-zero; we
        //    ignore that and proceed to the plist removal.
        let agentPath = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("studio.hypertext.curfew.lockdown.plist")

        if fileManager.fileExists(atPath: agentPath.path) {
            _ = runLaunchctl(["unload", agentPath.path])
            remove(at: agentPath, via: fileManager, removed: &removed, failed: &failed)
        }

        // 2. Application Support directory (activity.sqlite3, mcp-requests.json,
        //    the Unix socket file, etc.).
        let appSupport = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("Curfew", isDirectory: true)
        if fileManager.fileExists(atPath: appSupport.path) {
            remove(at: appSupport, via: fileManager, removed: &removed, failed: &failed)
        }

        // 3. Caches directory — bundle identifier, not display name, so the
        //    OS-created caches directory clears cleanly.
        let caches = home
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("studio.hypertext.curfew", isDirectory: true)
        if fileManager.fileExists(atPath: caches.path) {
            remove(at: caches, via: fileManager, removed: &removed, failed: &failed)
        }

        // 4. UserDefaults domain — `removePersistentDomain` is the official
        //    API but does not always flush the plist file. We follow up
        //    with a direct unlink so the file is gone even on machines
        //    where the defaults daemon hasn't flushed yet.
        UserDefaults.standard.removePersistentDomain(forName: SharedPaths.defaultsSuiteName)
        UserDefaults.standard.synchronize()
        let prefs = home
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(SharedPaths.defaultsSuiteName).plist")
        if fileManager.fileExists(atPath: prefs.path) {
            remove(at: prefs, via: fileManager, removed: &removed, failed: &failed)
        } else {
            // Still record the domain clear as a positive outcome so the
            // user sees that their settings were cleared.
            removed.append("UserDefaults: \(SharedPaths.defaultsSuiteName)")
        }

        uninstallLogger.info("Uninstall complete: \(removed.count) removed, \(failed.count) failed")
        return Outcome(removed: removed, failed: failed)
    }

    /// Shells out to `launchctl`. Returns the exit status — callers usually
    /// ignore it because "already unloaded" is an expected non-error case.
    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            uninstallLogger
                .warning(
                    "launchctl \(args.joined(separator: " ")) failed: \(error.localizedDescription)"
                )
            return -1
        }
    }

    /// Attempts to remove `url`, updating the caller's outcome arrays.
    /// Factored out so every removal step records the same shape.
    private static func remove(
        at url: URL,
        via fileManager: FileManager,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        do {
            try fileManager.removeItem(at: url)
            removed.append(url.path)
        } catch {
            failed.append((url.path, error.localizedDescription))
            uninstallLogger
                .error(
                    "remove failed at \(url.path, privacy: .public): \(error.localizedDescription)"
                )
        }
    }
}
