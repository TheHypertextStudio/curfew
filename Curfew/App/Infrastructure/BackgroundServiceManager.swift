import AppKit
import Combine
import CurfewKit
import Foundation
import ServiceManagement

/// Registers user-session recovery independently of the optional root daemon.
@MainActor
final class BackgroundServiceManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var lastError: String?
    @Published private(set) var supervisorHealthError: String?
    @Published private(set) var supervisorLastCheckedAt: Date?
    let isAvailable: Bool

    private let service: any AppServiceControlling
    private let preferences: UserDefaults?
    private let healthStore: SupervisorHealthStore
    private let canUnregister: Bool
    private var lastHealthPollAt: Date?
    private var enabledSince: Date?
    private let retireLegacyGuard: @MainActor () throws -> Void
    private var registrationAttempted = false
    private var legacyRetired = false
    private static let attemptedKey = "curfew.backgroundService.registrationAttempted.v1"

    nonisolated init(
        service: (any AppServiceControlling)? = nil,
        preferences: UserDefaults? = nil,
        healthStore: SupervisorHealthStore? = nil,
        retireLegacyGuard: (@MainActor () throws -> Void)? = nil
    ) {
        self.isAvailable = service != nil || Self.automaticRegistrationAllowed
        self
            .canUnregister = service != nil ||
            (!RuntimeEnvironment.isUnitTestHost && !RuntimeEnvironment.isDemoFixture)
        self.healthStore = healthStore ?? (Self.automaticRegistrationAllowed && service == nil
            ? .production() : SupervisorHealthStore())
        self.service = service ?? SystemAppServiceController(
            service: SMAppService.agent(plistName: CurfewFlavor.current.supervisorPlistName)
        )
        self.preferences = preferences ?? (Self.automaticRegistrationAllowed ? .standard : nil)
        self.retireLegacyGuard = retireLegacyGuard ?? {
            guard CurfewFlavor.current == .production else { return }
            try PersistentLockdown.production().uninstall()
        }
    }

    nonisolated static var automaticRegistrationAllowed: Bool {
        #if DEBUG
            let debugBuild = true
        #else
            let debugBuild = false
        #endif
        #if DEBUG && CURFEW_STAGING
            let stagingOptIn = Bundle.main.object(
                forInfoDictionaryKey: "CurfewAcceptanceFixture"
            ) as? Bool == true
        #else
            let stagingOptIn = false
        #endif
        return SupervisorRegistrationPolicy.allowsRegistration(
            debugBuild: debugBuild, explicitStagingOptIn: stagingOptIn,
            testHost: RuntimeEnvironment.isUnitTestHost, demo: RuntimeEnvironment.isDemoFixture
        )
    }

    func ensureRegistered() {
        guard isAvailable else { return }
        refreshStatus()
        guard status == .notRegistered || status == .notFound else { return }
        guard !registrationAttempted,
              preferences?.bool(forKey: Self.attemptedKey) != true else { return }
        register()
    }

    func register() {
        guard isAvailable else { return }
        registrationAttempted = true
        preferences?.set(true, forKey: Self.attemptedKey)
        do {
            try service.register()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    func refreshStatus() {
        guard isAvailable else { return }
        status = service.status
        refreshSupervisorHealthIfNeeded()
        guard status == .enabled, !legacyRetired else { return }
        do {
            try retireLegacyGuard()
            legacyRetired = true
            lastError = nil
        } catch {
            lastError = "Curfew could not remove its old recovery agent: \(error.localizedDescription)"
        }
    }

    /// Failure stops uninstall before any schedule or runtime state is removed.
    func unregister() throws {
        guard canUnregister else { return }
        guard service.status != .notRegistered, service.status != .notFound else { return }
        do {
            try service.unregister()
            status = service.status
            preferences?.removeObject(forKey: Self.attemptedKey)
            registrationAttempted = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func refreshSupervisorHealthIfNeeded(at now: Date = Date()) {
        guard isAvailable else { return }
        status = service.status
        guard status == .enabled else {
            enabledSince = nil
            supervisorLastCheckedAt = nil
            supervisorHealthError = nil
            return
        }
        if let lastHealthPollAt {
            let elapsed = now.timeIntervalSince(lastHealthPollAt)
            if elapsed >= 0, elapsed < 5 {
                return
            }
        }
        lastHealthPollAt = now
        if enabledSince == nil {
            enabledSince = now
        }
        do {
            guard let record = try healthStore.load() else {
                supervisorLastCheckedAt = nil
                supervisorHealthError = now.timeIntervalSince(enabledSince ?? now) >= 90
                    ?
                    "The supervisor has not checked in. Recovery after Quit is unconfirmed." :
                    nil
                return
            }
            supervisorLastCheckedAt = record.lastCheckedAt
            if !record.isFresh(at: now) {
                supervisorHealthError = "The supervisor has stopped checking in. " +
                    "Curfew may not recover after Quit."
            } else if let failure = record.launchFailure {
                supervisorHealthError = "Curfew could not restart in the background: \(failure)"
            } else {
                supervisorHealthError = nil
            }
        } catch {
            supervisorLastCheckedAt = nil
            supervisorHealthError = "Curfew cannot read its supervisor status: \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var isRecoveryHealthy: Bool {
        guard isEnabled, supervisorHealthError == nil,
              let supervisorLastCheckedAt else { return false }
        return SupervisorHealthRecord(lastCheckedAt: supervisorLastCheckedAt)
            .isFresh(at: lastHealthPollAt ?? Date())
    }

    var statusLine: String {
        switch status {
        case .enabled:
            if supervisorHealthError != nil {
                "Background recovery is degraded"
            } else if isRecoveryHealthy {
                "Background recovery is enabled"
            } else {
                "Background recovery is starting"
            }
        case .requiresApproval: "Background recovery needs approval"
        case .notRegistered, .notFound: "Background recovery is not enabled"
        @unknown default: "Background recovery status is unknown"
        }
    }

    var detail: String {
        switch status {
        case .enabled:
            isRecoveryHealthy
                ? "Curfew runs with every window closed and restarts in the background " +
                "after Quit or Force Quit."
                : "The service is registered. Curfew is waiting for a successful supervisor check."
        case .requiresApproval:
            "Allow Curfew in System Settings → General → Login Items & Extensions."
        case .notRegistered, .notFound:
            "Curfew can enforce while it is running, but cannot recover after Quit or Force Quit."
        @unknown default:
            "Open System Settings to check whether Curfew can run in the background."
        }
    }
}
