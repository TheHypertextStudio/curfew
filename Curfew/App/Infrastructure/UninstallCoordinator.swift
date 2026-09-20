import AppKit
import Foundation
import OSLog

private let uninstallLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "uninstall"
)

/// Orchestrates a complete uninstall of Curfew's local state.
///
/// Removes the five places the app writes on disk:
///   1. `~/Library/LaunchAgents/studio.hypertext.curfew.lockdown.plist` — the
///      `PersistentLockdown` respawn agent (best-effort `launchctl unload`
///      first so the agent doesn't re-launch the app mid-uninstall).
///   2. `~/Library/Application Support/Curfew/` — MCP queue, Unix socket,
///      and other legacy app-owned files.
///   3. `~/Library/Group Containers/group.studio.hypertext.curfew/Curfew/` —
///      shared activity SQLite plus the widget settings snapshot.
///   4. `~/Library/Preferences/studio.hypertext.curfew.plist` — UserDefaults
///      domain holding schedule, budgets, license key, settings.
///   5. `~/Library/Caches/studio.hypertext.curfew/` — incidental cache files.
///   6. Flavor-specific Curfew and Docket Keychain services — OAuth
///      credentials, device keys, Recovery Key material, and enrollment
///      checkpoints.
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
        ),
        defaultsSuiteName: String = SharedPaths.defaultsSuiteName,
        eraseKeychainService: (String) throws -> Void = KeychainAccountSecretStore.deleteAll
    ) -> Outcome {
        var removed: [String] = []
        var failed: [(path: String, reason: String)] = []

        guard prepareBrowserRemoval(home: home, failed: &failed) else {
            return Outcome(removed: removed, failed: failed)
        }

        // 1. Unload the LaunchAgent before deleting its plist so launchd
        //    does not respawn the app between `rm` and `launchctl`. The
        //    failure mode here is benign — if the agent was never loaded,
        //    `launchctl unload` prints a warning and exits non-zero; we
        //    ignore that and proceed to the plist removal.
        //
        //    The respawn agent is installed only by the production build (a
        //    development build uses `NoOpRespawnGuard`) and its label is
        //    deliberately flavor-neutral. So only a production uninstall may
        //    remove it — otherwise uninstalling a dev build would tear down
        //    the real install's respawn deterrent.
        removeRespawnAgentIfNeeded(
            home: home,
            fileManager: fileManager,
            removed: &removed,
            failed: &failed
        )

        // 2. Application Support directory (MCP queue, Unix socket, activity
        //    DBs, etc.). Flavor-suffixed — a dev uninstall clears `Curfew (Dev)`
        //    and leaves the production `Curfew` directory untouched.
        let appSupport = home.appendingPathComponent(
            "Library/Application Support/Curfew\(CurfewFlavor.current.displaySuffix)",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: appSupport.path) {
            remove(at: appSupport, via: fileManager, removed: &removed, failed: &failed)
        }

        // 3. Shared group-container directory used by the future widget target.
        let sharedSupport = home
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(SharedPaths.widgetAppGroupIdentifier, isDirectory: true)
            .appendingPathComponent("Curfew", isDirectory: true)
        if fileManager.fileExists(atPath: sharedSupport.path) {
            remove(at: sharedSupport, via: fileManager, removed: &removed, failed: &failed)
        }

        // 4. Caches directory — keyed by bundle identifier (so flavor-suffixed
        //    for dev), not display name, so the OS-created caches directory
        //    clears cleanly.
        let caches = home
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent(
                "studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix)",
                isDirectory: true
            )
        if fileManager.fileExists(atPath: caches.path) {
            remove(at: caches, via: fileManager, removed: &removed, failed: &failed)
        }

        // 5. UserDefaults domain — `removePersistentDomain` is the official
        //    API but does not always flush the plist file. We follow up
        //    with a direct unlink so the file is gone even on machines
        //    where the defaults daemon hasn't flushed yet.
        eraseUserDefaults(
            suiteName: defaultsSuiteName,
            home: home,
            fileManager: fileManager,
            removed: &removed,
            failed: &failed
        )

        // 6. Account Keychain state. The service follows the current flavor,
        // so removing Curfew Dev never signs the production app out. This must
        // include dynamic device-key accounts and the durable ready marker;
        // deleting known account names individually would inevitably miss new
        // credentials added later.
        eraseAccountKeychain(
            using: eraseKeychainService,
            removed: &removed,
            failed: &failed
        )

        uninstallLogger.info("Uninstall complete: \(removed.count) removed, \(failed.count) failed")
        return Outcome(removed: removed, failed: failed)
    }

    private static func removeRespawnAgentIfNeeded(
        home: URL,
        fileManager: FileManager,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        guard CurfewFlavor.current == .production else { return }
        let agentPath = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("studio.hypertext.curfew.lockdown.plist")
        guard fileManager.fileExists(atPath: agentPath.path) else { return }
        _ = runLaunchctl(["unload", agentPath.path])
        remove(at: agentPath, via: fileManager, removed: &removed, failed: &failed)
    }

    private static func prepareBrowserRemoval(
        home: URL,
        failed: inout [(path: String, reason: String)]
    ) -> Bool {
        guard revokeBrowserInstallation(home: home, failed: &failed) else {
            return false
        }
        removeBrowserManifest(home: home, failed: &failed)
        return true
    }

    private static func eraseUserDefaults(
        suiteName: String,
        home: URL,
        fileManager: FileManager,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.synchronize()
        let prefs = home
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(suiteName).plist")
        if fileManager.fileExists(atPath: prefs.path) {
            remove(at: prefs, via: fileManager, removed: &removed, failed: &failed)
        } else {
            removed.append("UserDefaults: \(suiteName)")
        }
    }

    private static func eraseAccountKeychain(
        using eraseKeychainService: (String) throws -> Void,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        let keychainServices = accountKeychainServices(
            flavor: .current,
            curfewService: CurfewServiceEndpoints.current.keychainService,
            docketService: DocketServiceEndpoints.current.keychainService
        )
        for keychainService in keychainServices {
            do {
                try eraseKeychainService(keychainService)
                removed.append("Keychain: \(keychainService)")
            } catch {
                failed.append((
                    "Keychain: \(keychainService)",
                    "Could not remove account credentials."
                ))
            }
        }
    }

    /// Services safe for the running flavor to remove. The legacy coordinator
    /// credential predates flavor isolation and is production-owned; a Dev
    /// uninstall must preserve it rather than signing the real app out.
    static func accountKeychainServices(
        flavor: CurfewFlavor,
        curfewService: String,
        docketService: String
    ) -> [String] {
        var services = [curfewService, docketService]
        if flavor == .production {
            services.append(KeychainDeviceAssertionSecretStore.service)
        }
        return services
    }

    private static func revokeBrowserInstallation(
        home: URL,
        failed: inout [(path: String, reason: String)]
    ) -> Bool {
        do {
            let directory = BrowserNativeInstallation.browserDirectory(home: home, flavor: .current)
            try BrowserNativeStore(directory: directory).deactivate()
            return true
        } catch {
            failed.append(("Chrome native host", "Could not revoke the native host installation."))
            return false
        }
    }

    private static func removeBrowserManifest(
        home: URL,
        failed: inout [(path: String, reason: String)]
    ) {
        do {
            try BrowserNativeInstallation.removeManifest(
                home: home,
                executable: Bundle.main.bundleURL.appendingPathComponent(
                    "Contents/Resources/studio.hypertext.curfew.browser"
                )
            )
        } catch {
            failed.append(("Chrome native host", "Could not remove the native host manifest."))
        }
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

/// Guarantees that no live model can recreate state after uninstall cleanup.
@MainActor
enum UninstallLifecycle {
    static func finish(
        outcome: UninstallCoordinator.Outcome,
        present: (UninstallCoordinator.Outcome) -> Void,
        terminate: () -> Void
    ) {
        present(outcome)
        terminate()
    }
}
