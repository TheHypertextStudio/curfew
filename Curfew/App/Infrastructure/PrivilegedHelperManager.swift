import AppKit
import Combine
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

/// Observable state machine for the `SMAppService`-managed LaunchDaemon and
/// the app's login item registration.
///
/// v0.1 bypass protection relies on a root-owned LaunchDaemon
/// (`studio.hypertext.curfew.daemon`) that:
/// 1. Accepts deadline and heartbeat RPCs only from the signed Curfew app.
/// 2. Atomically owns root state and schedules shutdown once when a live
///    deadline outlasts its 90-second app heartbeat.
///
/// The daemon plist lives under `Curfew.app/Contents/Library/LaunchDaemons/`.
/// Production and development use separate plist names and launchd labels so
/// a staging acceptance build cannot replace the user's production helper.
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

    /// Invalidates scheduling receipts across removal, replacement and maintenance.
    private(set) var sunriseOwnershipRevision: UInt64 = 0

    /// Installation state of the privileged daemon.
    private(set) var daemonStatus: SMAppService.Status = .notRegistered {
        didSet {
            if oldValue != daemonStatus {
                sunriseOwnershipRevision &+= 1
            }
        }
    }

    /// Registration state of the main-app login item.
    private(set) var loginItemStatus: SMAppService.Status = .notRegistered

    /// Most recent error from `install()` or `uninstall()`, shown in the UI.
    var lastError: String?

    /// Registration alone is not proof that the LaunchDaemon is still running.
    var isDaemonResponding: Bool {
        guard daemonStatus == .enabled,
              let attributes = try? FileManager.default.attributesOfItem(
                  atPath: daemonHeartbeatURL.path
              ),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modifiedAt = attributes[.modificationDate] as? Date
        else { return false }
        let age = now().timeIntervalSince(modifiedAt)
        return age >= 0 && age <= 45
    }

    var isRemoteLockEnforcementAvailable: Bool {
        guard isDaemonResponding, connectionState == .ready else { return false }
        let owner = liveEnforcementOwnerOverride?() ?? currentLiveEnforcementOwner()
        return !DevelopmentDaemonSafety.shouldStandDown(
            flavor: flavor,
            owner: owner,
            ownerIsLive: owner != nil
        )
    }

    /// Runtime health of the authenticated XPC channel, separate from launchd registration.
    var connectionState: ConnectionState = .unavailable
    var repairInProgress = false
    var installationInProgress = false
    var maintenancePaused = false {
        didSet {
            if oldValue != maintenancePaused {
                sunriseOwnershipRevision &+= 1
            }
        }
    }

    @ObservationIgnored let registrationRepair = DaemonRegistrationRepair()

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

    private nonisolated static var daemonPlistName: String {
        CurfewFlavor.current.daemonPlistName
    }

    let daemonService: any AppServiceControlling
    private let loginItemService: any AppServiceControlling
    private let daemonHeartbeatURL: URL
    private let now: () -> Date
    private let flavor: CurfewFlavor
    private let liveEnforcementOwnerOverride: (() -> EnforcementOwner?)?
    let daemonRPC: any PrivilegedDaemonRPCControlling

    // MARK: - Lifecycle

    /// Default-initialized; `SMAppService` handles are derived from the
    /// constant daemon plist name on the main actor.
    init(
        daemonService: (any AppServiceControlling)? = nil,
        loginItemService: (any AppServiceControlling)? = nil,
        daemonHeartbeatURL: URL? = nil,
        now: @escaping () -> Date = Date.init,
        flavor: CurfewFlavor? = nil,
        liveEnforcementOwner: (() -> EnforcementOwner?)? = nil,
        daemonRPC: (any PrivilegedDaemonRPCControlling)? = nil
    ) {
        self.daemonService = daemonService ?? SystemAppServiceController(
            service: SMAppService.daemon(plistName: Self.daemonPlistName)
        )
        self.loginItemService = loginItemService ?? SystemAppServiceController(
            service: SMAppService.mainApp
        )
        self.daemonRPC = daemonRPC ?? XPCPrivilegedDaemonClient()
        self.daemonHeartbeatURL = daemonHeartbeatURL ?? SharedPaths.privilegedApplicationSupport
            .appendingPathComponent(".daemon-alive")
        self.now = now
        self.flavor = flavor ?? .current
        self.liveEnforcementOwnerOverride = liveEnforcementOwner
    }

    private func currentLiveEnforcementOwner() -> EnforcementOwner? {
        guard let owner = EnforcementOwnerStore.load(from: SharedPaths.enforcementOwnerLock),
              owner.hasRecognizedIdentity,
              let app = NSRunningApplication(processIdentifier: owner.processIdentifier),
              app.bundleIdentifier == owner.bundleIdentifier
        else { return nil }
        return owner
    }

    // MARK: - Daemon

    /// Registers the LaunchDaemon with the system. macOS will prompt the user
    /// for authorisation. Throws an `SMAppServiceError` on failure.
    func installDaemon() {
        guard !repairInProgress else { return }
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
        guard !repairInProgress else { return }
        sunriseOwnershipRevision &+= 1
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
        guard !repairInProgress else { return false }
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
        guard !maintenancePaused, !repairInProgress else { return }
        await performRPC { try await daemonRPC.armLockout(record) }
    }

    func heartbeat(lockoutID: UUID) async {
        await performRPC { try await daemonRPC.heartbeat(lockoutID: lockoutID) }
    }

    @discardableResult
    func completeLockout(lockoutID: UUID, reason: PrivilegedCompletionReason) async -> Bool {
        await performRPC {
            try await daemonRPC.completeLockout(lockoutID: lockoutID, reason: reason)
        }
    }

    @discardableResult
    private func performRPC(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            connectionState = .ready
            lastError = nil
            return true
        } catch {
            recordRPCError(error)
            return false
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

    /// An isolated app must remove its launchd registrations before erasing
    /// state or asking the user to trash its bundle. Attempt both removals so
    /// one failure does not leave the other registration behind.
    func unregisterForUninstall() -> [String] {
        sunriseOwnershipRevision &+= 1
        var failures: [String] = []
        if daemonService.status != .notRegistered, daemonService.status != .notFound {
            do {
                try daemonService.unregister()
            } catch {
                failures.append("Privileged daemon: \(error.localizedDescription)")
            }
        }
        if loginItemService.status != .notRegistered, loginItemService.status != .notFound {
            do {
                try loginItemService.unregister()
            } catch {
                failures.append("Login item: \(error.localizedDescription)")
            }
        }
        refreshStatus()
        lastError = failures.first
        return failures
    }
}

extension PrivilegedHelperManager {
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

    /// Refresh registration state after launch or an installation change.
    func refreshStatus() {
        daemonStatus = daemonService.status
        loginItemStatus = loginItemService.status
        let daemonDesc = daemonStatus.debugDescription
        let loginDesc = loginItemStatus.debugDescription
        helperLogger.info(
            "helper status: daemon=\(daemonDesc, privacy: .public) loginItem=\(loginDesc, privacy: .public)"
        )
    }

    #if DEBUG
        func seedDemoStatus(
            daemon: SMAppService.Status = .notRegistered,
            login: SMAppService.Status = .notRegistered,
            connection: ConnectionState = .unavailable
        ) {
            daemonStatus = daemon
            loginItemStatus = login
            connectionState = connection
            lastError = connection == .ready ? nil : "Background protection is not connected."
        }

        func seedDemoUnavailableError() {
            daemonStatus = .notRegistered
            connectionState = .unavailable
            lastError = PrivilegedDaemonRPCError.unavailable.localizedDescription
        }

        func seedConnectionStateForTesting(_ state: ConnectionState) {
            connectionState = state
        }
    #endif
}
