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
    /// Executes the full uninstall sequence synchronously on the main actor.
    /// Returns an `Outcome` describing every path touched.
    @discardableResult
    static func performUninstall(
        fileManager: FileManager = .default,
        home: URL = URL(
            fileURLWithPath: NSHomeDirectory(),
            isDirectory: true
        ),
        flavor: CurfewFlavor = .current,
        defaultsSuiteName: String? = nil,
        unregisterServices: (() -> [String])? = nil,
        eraseKeychainService: (String) throws -> Void = KeychainAccountSecretStore.deleteAll
    ) -> Outcome {
        if let blocked = registrationPreflight(
            flavor: flavor,
            unregisterServices: unregisterServices
        ) {
            return blocked
        }
        var removed: [String] = []
        var failed: [(path: String, reason: String)] = []

        guard prepareBrowserRemoval(home: home, flavor: flavor, failed: &failed) else {
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
            flavor: flavor,
            fileManager: fileManager,
            removed: &removed,
            failed: &failed
        )

        // 2–4. Remove only this flavor's Application Support, group, and cache.
        removeLocalDirectories(
            home: home,
            flavor: flavor,
            fileManager: fileManager,
            removed: &removed,
            failed: &failed
        )

        // 5. UserDefaults domain — `removePersistentDomain` is the official
        //    API but does not always flush the plist file. We follow up
        //    with a direct unlink so the file is gone even on machines
        //    where the defaults daemon hasn't flushed yet.
        eraseUserDefaults(
            suiteName: defaultsSuiteName ?? SharedPaths.defaultsSuiteName(for: flavor),
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
            flavor: flavor,
            using: eraseKeychainService,
            removed: &removed,
            failed: &failed
        )

        uninstallLogger.info("Uninstall complete: \(removed.count) removed, \(failed.count) failed")
        return Outcome(removed: removed, failed: failed)
    }

    private static func removeLocalDirectories(
        home: URL,
        flavor: CurfewFlavor,
        fileManager: FileManager,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        let paths = [
            home.appendingPathComponent(
                "Library/Application Support/Curfew\(flavor.displaySuffix)",
                isDirectory: true
            ),
            home.appendingPathComponent("Library/Group Containers", isDirectory: true)
                .appendingPathComponent(
                    SharedPaths.widgetAppGroupIdentifier(for: flavor),
                    isDirectory: true
                )
                .appendingPathComponent("Curfew", isDirectory: true),
            home.appendingPathComponent("Library/Caches", isDirectory: true)
                .appendingPathComponent(
                    SharedPaths.defaultsSuiteName(for: flavor),
                    isDirectory: true
                )
        ]
        for path in paths where fileManager.fileExists(atPath: path.path) {
            remove(at: path, via: fileManager, removed: &removed, failed: &failed)
        }
    }

    private static func removeRespawnAgentIfNeeded(
        home: URL,
        flavor: CurfewFlavor,
        fileManager: FileManager,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        guard flavor == .production else { return }
        let agentPath = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("studio.hypertext.curfew.lockdown.plist")
        guard fileManager.fileExists(atPath: agentPath.path) else { return }
        _ = runLaunchctl(["unload", agentPath.path])
        remove(at: agentPath, via: fileManager, removed: &removed, failed: &failed)
    }

    private static func prepareBrowserRemoval(
        home: URL,
        flavor: CurfewFlavor,
        failed: inout [(path: String, reason: String)]
    ) -> Bool {
        guard revokeBrowserInstallation(home: home, flavor: flavor, failed: &failed) else {
            return false
        }
        removeBrowserManifest(home: home, flavor: flavor, failed: &failed)
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
        flavor: CurfewFlavor,
        using eraseKeychainService: (String) throws -> Void,
        removed: inout [String],
        failed: inout [(path: String, reason: String)]
    ) {
        let keychainServices = accountKeychainServices(
            flavor: flavor,
            curfewService: CurfewServiceEndpoints.forFlavor(flavor).keychainService,
            docketService: DocketServiceEndpoints.forFlavor(flavor).keychainService
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
            services.append(KeychainDeviceAssertionSecretStore.service(for: .production))
        } else if flavor == .studioDevelopment {
            services.append(KeychainDeviceAssertionSecretStore.service(for: .studioDevelopment))
        }
        return services
    }

    static func appBundleURL(for flavor: CurfewFlavor) -> URL {
        URL(fileURLWithPath: flavor == .studioDevelopment
            ? "/Applications/Curfew Studio Dev.app"
            : "/Applications/Curfew.app")
    }

    private static func revokeBrowserInstallation(
        home: URL,
        flavor: CurfewFlavor,
        failed: inout [(path: String, reason: String)]
    ) -> Bool {
        do {
            let directory = BrowserNativeInstallation.browserDirectory(home: home, flavor: flavor)
            try BrowserNativeStore(directory: directory).deactivate()
            return true
        } catch {
            failed.append(("Chrome native host", "Could not revoke the native host installation."))
            return false
        }
    }

    private static func removeBrowserManifest(
        home: URL,
        flavor: CurfewFlavor,
        failed: inout [(path: String, reason: String)]
    ) {
        do {
            try BrowserNativeInstallation.removeManifest(
                home: home,
                executable: Bundle.main.bundleURL.appendingPathComponent(
                    "Contents/Resources/studio.hypertext.curfew.browser"
                ),
                flavor: flavor
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
