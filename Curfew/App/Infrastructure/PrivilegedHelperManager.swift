import CurfewKit
import Foundation
import Observation
import OSLog
import ServiceManagement
import SwiftUI

private let helperLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "privileged-helper"
)

protocol AppServiceControlling {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

private struct SystemAppServiceController: AppServiceControlling {
    let service: SMAppService

    var status: SMAppService.Status {
        service.status
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

/// Observable state machine for the `SMAppService`-managed LaunchDaemon and
/// the app's login item registration.
///
/// v0.1 bypass protection relies on a root-owned LaunchDaemon
/// (`studio.hypertext.curfew.daemon`) that:
/// 1. Accepts deadline and heartbeat RPCs only from the signed Curfew app.
/// 2. Atomically owns root state and schedules shutdown once when a live
///    deadline outlasts its 90-second app heartbeat.
///
/// The daemon plist lives at
/// `Curfew.app/Contents/Library/LaunchDaemons/studio.hypertext.curfew.daemon.plist`.
/// SMAppService handles the installation; the user authorises via an
/// interactive macOS system prompt the first time `install()` is called.
///
/// The login item uses `SMAppService.mainApp` so Curfew restarts automatically
/// at login without the legacy `LaunchAgent` approach — this pairs with the
/// existing `PersistentLockdown` LaunchAgent for defense in depth.
@MainActor
@Observable
final class PrivilegedHelperManager {
    enum ConnectionState: Equatable {
        case ready
        case unavailable
        case unauthorized
        case stale
        case registrationFailed
    }

    /// Installation state of the privileged daemon.
    private(set) var daemonStatus: SMAppService.Status = .notRegistered

    /// Registration state of the main-app login item.
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    /// Most recent error from `install()` or `uninstall()`, shown in the UI.
    private(set) var lastError: String?

    /// Runtime health of the authenticated XPC channel, separate from launchd registration.
    private(set) var connectionState: ConnectionState = .unavailable

    var enforcementAvailability: PrivilegedEnforcementAvailability {
        switch connectionState {
        case .ready: .ready
        case .unavailable: .unavailable
        case .unauthorized: .unauthorized
        case .stale: .stale
        case .registrationFailed: .registrationFailed
        }
    }

    // MARK: - SMAppService handles

    private static let daemonPlistName = "studio.hypertext.curfew.daemon.plist"
    private let daemonService: any AppServiceControlling
    private let loginItemService: any AppServiceControlling
    private let daemonRPC: any PrivilegedDaemonRPCControlling

    // MARK: - Lifecycle

    /// Default-initialized; `SMAppService` handles are derived from the
    /// constant daemon plist name on the main actor.
    init(
        daemonService: (any AppServiceControlling)? = nil,
        loginItemService: (any AppServiceControlling)? = nil,
        daemonRPC: (any PrivilegedDaemonRPCControlling)? = nil
    ) {
        self.daemonService = daemonService ?? SystemAppServiceController(
            service: SMAppService.daemon(plistName: Self.daemonPlistName)
        )
        self.loginItemService = loginItemService ?? SystemAppServiceController(
            service: SMAppService.mainApp
        )
        self.daemonRPC = daemonRPC ?? XPCPrivilegedDaemonClient()
    }

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
            connectionState = .unavailable
            helperLogger.info("privileged daemon registered")
        } catch {
            lastError = error.localizedDescription
            connectionState = .registrationFailed
            helperLogger
                .error("daemon register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Unregisters the LaunchDaemon. The daemon binary and plist remain on
    /// disk — only the system registration is removed.
    func uninstallDaemon() async {
        do {
            try await daemonRPC.prepareForUninstall()
            try daemonService.unregister()
            daemonStatus = .notRegistered
            connectionState = .unavailable
            lastError = nil
            helperLogger.info("privileged daemon unregistered")
        } catch {
            lastError = error.localizedDescription
            helperLogger
                .error("daemon unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes privileged and login-item registrations before user data is deleted.
    func prepareForFullUninstall() async -> Bool {
        lastError = nil
        refreshStatus()
        if daemonStatus == .enabled {
            await uninstallDaemon()
            guard daemonStatus == .notRegistered, lastError == nil else { return false }
        } else if daemonStatus == .requiresApproval {
            do {
                try daemonService.unregister()
                daemonStatus = .notRegistered
            } catch {
                lastError = error.localizedDescription
                connectionState = .registrationFailed
                return false
            }
        }

        if loginItemStatus == .enabled || loginItemStatus == .requiresApproval {
            unregisterLoginItem()
        }
        return lastError == nil
    }

    @discardableResult
    func reconcileDaemonStatus() async -> PrivilegedDaemonStatus? {
        do {
            let status = try await daemonRPC.status()
            if let heartbeat = status.lastHeartbeatAt,
               status.activeRecord != nil,
               Date().timeIntervalSince(heartbeat) > PrivilegedDaemonConstants.heartbeatTimeout {
                connectionState = .stale
                lastError = PrivilegedDaemonRPCError.stale.localizedDescription
            } else {
                connectionState = .ready
                lastError = nil
            }
            return status
        } catch {
            recordRPCError(error)
            return nil
        }
    }

    func armLockout(_ record: LockoutDeadlineRecord) async {
        await performRPC { try await daemonRPC.armLockout(record) }
    }

    func heartbeat(lockoutID: UUID) async {
        await performRPC { try await daemonRPC.heartbeat(lockoutID: lockoutID) }
    }

    func completeLockout(lockoutID: UUID, reason: PrivilegedCompletionReason) async {
        await performRPC {
            try await daemonRPC.completeLockout(lockoutID: lockoutID, reason: reason)
        }
    }

    private func performRPC(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            connectionState = .ready
            lastError = nil
        } catch {
            recordRPCError(error)
        }
    }

    private func recordRPCError(_ error: Error) {
        let rpcError = error as? PrivilegedDaemonRPCError ?? .unavailable
        switch rpcError {
        case .unauthorized:
            connectionState = .unauthorized
        case .stale:
            connectionState = .stale
        case .activeLockout, .invalidResponse, .unavailable:
            connectionState = .unavailable
        }
        lastError = rpcError.localizedDescription
        helperLogger.error("daemon RPC failed: \(rpcError.localizedDescription, privacy: .public)")
    }

    #if DEBUG
        func seedDemoUnavailableError() {
            daemonStatus = .notRegistered
            connectionState = .unavailable
            lastError = PrivilegedDaemonRPCError.unavailable.localizedDescription
        }

        func seedConnectionStateForTesting(_ state: ConnectionState) {
            connectionState = state
        }
    #endif

    // MARK: - Login item

    /// Registers the main app as a login item via SMAppService. Replaces the
    /// legacy `LaunchAgent` approach; both coexist for defense in depth.
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
