import Combine
import Foundation
import OSLog
import ServiceManagement
import SwiftUI

private let helperLogger = Logger(subsystem: "studio.hypertext.curfew", category: "privileged-helper")

/// Observable state machine for the `SMAppService`-managed LaunchDaemon and
/// the app's login item registration.
///
/// v0.2 bypass protection relies on a root-owned LaunchDaemon
/// (`studio.hypertext.curfew.daemon`) that:
/// 1. Reads the lockout-state file at `SharedPaths.lockoutStatePath`.
/// 2. Calls `shutdown -h now` if the file says `locked` and the machine has
///    been unlocked (jailbroken from lockout) — providing a root-enforced
///    consequence that the user-space `PersistentLockdown` LaunchAgent cannot.
///
/// The daemon plist lives at
/// `Curfew.app/Contents/Library/LaunchDaemons/studio.hypertext.curfew.daemon.plist`.
/// SMAppService handles the installation; the user authorises via an
/// interactive macOS system prompt the first time `install()` is called.
///
/// The login item uses `SMAppService.mainApp` so Curfew restarts automatically
/// at login without the legacy `LaunchAgent` approach — this pairs with the
/// existing `PersistentLockdown` LaunchAgent for defence-in-depth in v0.2.
@MainActor
final class PrivilegedHelperManager: ObservableObject {
    /// Installation state of the privileged daemon.
    @Published private(set) var daemonStatus: SMAppService.Status = .notRegistered

    /// Registration state of the main-app login item.
    @Published private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    /// Most recent error from `install()` or `uninstall()`, shown in the UI.
    @Published private(set) var lastError: String?

    // MARK: - SMAppService handles

    private static let daemonPlistName = "studio.hypertext.curfew.daemon.plist"

    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: Self.daemonPlistName)
    }

    private var loginItemService: SMAppService {
        SMAppService.mainApp
    }

    // MARK: - Lifecycle

    nonisolated init() {}

    /// Refreshes `daemonStatus` and `loginItemStatus` from the system.
    /// Call this on app launch and after any `install` / `uninstall` attempt.
    func refreshStatus() {
        daemonStatus = daemonService.status
        loginItemStatus = loginItemService.status
        let daemonDesc = daemonStatus.debugDescription
        let loginDesc = loginItemStatus.debugDescription
        helperLogger.info(
            "helper status: daemon=\(daemonDesc, privacy: .public) loginItem=\(loginDesc, privacy: .public)"
        )
    }

    // MARK: - Daemon

    /// Registers the LaunchDaemon with the system. macOS will prompt the user
    /// for authorisation. Throws an `SMAppServiceError` on failure.
    func installDaemon() {
        do {
            try daemonService.register()
            daemonStatus = daemonService.status
            lastError = nil
            helperLogger.info("privileged daemon registered")
        } catch {
            lastError = error.localizedDescription
            helperLogger.error("daemon register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Unregisters the LaunchDaemon. The daemon binary and plist remain on
    /// disk — only the system registration is removed.
    func uninstallDaemon() {
        do {
            try daemonService.unregister()
            daemonStatus = .notRegistered
            lastError = nil
            helperLogger.info("privileged daemon unregistered")
        } catch {
            lastError = error.localizedDescription
            helperLogger.error("daemon unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Login item

    /// Registers the main app as a login item via SMAppService. Replaces the
    /// legacy `LaunchAgent` approach — both co-exist in v0.2 for
    /// defence-in-depth.
    func registerLoginItem() {
        do {
            try loginItemService.register()
            loginItemStatus = loginItemService.status
            lastError = nil
            helperLogger.info("login item registered")
        } catch {
            lastError = error.localizedDescription
            helperLogger.error(
                "login item register failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Removes the app from login items. The `PersistentLockdown` LaunchAgent
    /// is unaffected — it must be uninstalled separately via its own API.
    func unregisterLoginItem() {
        do {
            try loginItemService.unregister()
            loginItemStatus = .notRegistered
            lastError = nil
            helperLogger.info("login item unregistered")
        } catch {
            lastError = error.localizedDescription
            helperLogger.error(
                "login item unregister failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

private extension SMAppService.Status {
    /// Short human-readable description used for log messages.
    var debugDescription: String {
        switch self {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
