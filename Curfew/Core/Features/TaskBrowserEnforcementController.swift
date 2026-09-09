import Combine
import Foundation
import SwiftUI

nonisolated struct TaskBrowserIntegrationStatus: Equatable, Sendable {
    let detail: String
    let isHealthy: Bool
}

nonisolated struct TaskBrowserEnforcementViewModel: Equatable, Sendable {
    let docketAuthorization: TaskBrowserIntegrationStatus
    let docketPoll: TaskBrowserIntegrationStatus
    let extensionHeartbeat: TaskBrowserIntegrationStatus
    let nativeHost: TaskBrowserIntegrationStatus
    let enforcementReadiness: TaskBrowserIntegrationStatus
    let activeTaskTitle: String?
    let canToggleEnforcement: Bool
    let enforcementEnabled: Bool
    let canBeginBreak: Bool
    let breakEndsAt: Date?

    init(
        settings: BrowserIntegrationSettings,
        isAuthorized: Bool,
        lastSuccessfulPoll: Date?,
        docketIsHealthy: Bool,
        nativeHealth: BrowserNativeHealth?,
        hostIsInstalled: Bool,
        installationError: String?,
        policy: BrowserPolicySnapshot?,
        canBeginBreak: Bool,
        now: Date
    ) {
        let pollIsFresh = docketIsHealthy && Self.isFresh(lastSuccessfulPoll, at: now)
        let extensionSeenAt: Date? = nativeHealth.flatMap { health -> Date? in
            guard !health.extensionOrigin.isEmpty, health.extensionSeenAt != .distantPast else {
                return nil
            }
            return health.extensionSeenAt
        }
        let extensionIsFresh = Self.isFresh(extensionSeenAt, at: now)
        let hostIsFresh = Self.isFresh(nativeHealth?.hostSeenAt, at: now)
        let hostIsHealthy = installationError == nil && hostIsInstalled && hostIsFresh
        let isReady = settings.setupIsComplete && isAuthorized && pollIsFresh &&
            extensionIsFresh && hostIsHealthy

        self.docketAuthorization = .init(
            detail: isAuthorized ? "Connected" : "Not connected",
            isHealthy: isAuthorized
        )
        self.docketPoll = .init(
            detail: lastSuccessfulPoll.map { Self.lastSeen($0, at: now) } ?? "Never",
            isHealthy: pollIsFresh
        )
        self.extensionHeartbeat = .init(
            detail: extensionSeenAt.map { Self.lastSeen($0, at: now) } ?? "Never",
            isHealthy: extensionIsFresh
        )
        if let installationError {
            self.nativeHost = .init(detail: installationError, isHealthy: false)
        } else if !hostIsInstalled {
            self.nativeHost = .init(detail: "Not installed", isHealthy: false)
        } else {
            self.nativeHost = .init(
                detail: hostIsFresh ? "Installed and responding" : "Installed but unavailable",
                isHealthy: hostIsFresh
            )
        }
        self.enforcementReadiness = .init(
            detail: isReady ? "Ready" : "Not ready",
            isHealthy: isReady
        )
        self.activeTaskTitle = policy?.task.title
        self.canToggleEnforcement = settings.setupIsComplete
        self.enforcementEnabled = settings.enforcementEnabled
        self.canBeginBreak = canBeginBreak
        self.breakEndsAt = policy?.breakEndsAt.flatMap { $0 > now ? $0 : nil }
    }

    private static func isFresh(_ date: Date?, at now: Date) -> Bool {
        guard let date else { return false }
        return date <= now.addingTimeInterval(5) && now.timeIntervalSince(date) <= 60
    }

    private static func lastSeen(_ date: Date, at now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 {
            return "Last seen just now"
        }
        let minutes = elapsed / 60
        return "Last seen \(minutes) minute\(minutes == 1 ? "" : "s") ago"
    }
}

@MainActor
final class TaskBrowserEnforcementController: ObservableObject {
    @Published private(set) var settings: BrowserIntegrationSettings
    @Published private(set) var viewModel: TaskBrowserEnforcementViewModel
    @Published private(set) var errorMessage: String?

    private let runtime: BrowserNativeRuntime
    private let settingsStore: BrowserIntegrationSettingsStore
    private let now: () -> Date
    private var healthMonitorTask: Task<Void, Never>?

    init(
        runtime: BrowserNativeRuntime,
        settingsStore: BrowserIntegrationSettingsStore,
        now: @escaping () -> Date = Date.init,
        healthUpdates: AsyncStream<Date>? = nil
    ) {
        self.runtime = runtime
        self.settingsStore = settingsStore
        self.now = now
        let settings = settingsStore.load()
        self.settings = settings
        let date = now()
        self.viewModel = Self.makeViewModel(
            runtime: runtime,
            settings: settings,
            at: date
        )
        runtime.coordinator.onAuthenticatedPoll = { [weak self] date in
            self?.recordDocketConnection(at: date)
        }
        runtime.configureEnforcementForStartup(settings.enforcementEnabled)
        runtime.coordinator.replaceMappings(settings.mappings, at: date)
        refresh(at: date)
        let updates = healthUpdates ?? Self.fiveSecondHealthUpdates(now: now)
        self.healthMonitorTask = Task { @MainActor [weak self] in
            for await date in updates {
                guard !Task.isCancelled else { return }
                self?.refresh(at: date)
            }
        }
    }

    deinit {
        healthMonitorTask?.cancel()
    }

    func refresh(at date: Date? = nil) {
        let date = date ?? now()
        if let health = runtime.health(at: date),
           Self.isFresh(health.extensionSeenAt, at: date),
           !settings.chromeConnectedOnce {
            settings.recordChromeConnection()
            settingsStore.save(settings)
        }
        viewModel = Self.makeViewModel(runtime: runtime, settings: settings, at: date)
    }

    @discardableResult
    func setEnforcementEnabled(_ enabled: Bool, at date: Date? = nil) -> Bool {
        let date = date ?? now()
        var updatedSettings = settings
        guard updatedSettings.setEnforcementEnabled(enabled) else {
            refresh(at: date)
            return false
        }
        do {
            try runtime.setEnforcementEnabled(enabled, at: date)
            settings = updatedSettings
            settingsStore.save(settings)
            errorMessage = nil
        } catch {
            errorMessage = "Curfew could not update Chrome browser enforcement."
            refresh(at: date)
            return false
        }
        refresh(at: date)
        return true
    }

    func connect(at date: Date? = nil) async throws {
        let date = date ?? now()
        do {
            try await runtime.coordinator.connect(at: date)
            errorMessage = nil
            refresh(at: date)
        } catch {
            errorMessage = "Curfew could not connect to Docket."
            refresh(at: date)
            throw error
        }
    }

    func disconnect(at date: Date? = nil) async throws {
        let date = date ?? now()
        do {
            try await runtime.coordinator.disconnect(at: date)
            errorMessage = nil
            refresh(at: date)
        } catch {
            errorMessage = "Curfew could not disconnect Docket."
            refresh(at: date)
            throw error
        }
    }

    @discardableResult
    func addMapping(
        selector: WorkDestinationSelector,
        destination: String,
        scopeKind: BrowserDestinationScope.Kind,
        at date: Date? = nil
    ) throws -> WorkDestinationMapping {
        let date = date ?? now()
        do {
            let mapping = try settings.addMapping(
                selector: selector,
                destination: destination,
                scopeKind: scopeKind
            )
            settingsStore.save(settings)
            runtime.coordinator.replaceMappings(settings.mappings, at: date)
            errorMessage = nil
            refresh(at: date)
            return mapping
        } catch {
            errorMessage = "Use a valid ID and an exact HTTP or HTTPS origin or path."
            refresh(at: date)
            throw error
        }
    }

    func removeMapping(id: String, at date: Date? = nil) {
        let date = date ?? now()
        settings.removeMapping(id: id)
        settingsStore.save(settings)
        runtime.coordinator.replaceMappings(settings.mappings, at: date)
        errorMessage = nil
        refresh(at: date)
    }

    @discardableResult
    func beginBreak(at date: Date? = nil) -> Bool {
        let date = date ?? now()
        let didBegin = runtime.coordinator.beginBreak(at: date)
        refresh(at: date)
        return didBegin
    }

    private func recordDocketConnection(at date: Date) {
        if !settings.docketConnectedOnce {
            settings.recordDocketConnection()
            settingsStore.save(settings)
        }
        refresh(at: date)
    }

    private static func makeViewModel(
        runtime: BrowserNativeRuntime,
        settings: BrowserIntegrationSettings,
        at date: Date
    ) -> TaskBrowserEnforcementViewModel {
        TaskBrowserEnforcementViewModel(
            settings: settings,
            isAuthorized: runtime.coordinator.isAuthorized,
            lastSuccessfulPoll: runtime.coordinator.lastSuccessfulPoll,
            docketIsHealthy: runtime.coordinator.lastPollIsHealthy,
            nativeHealth: runtime.health(at: date),
            hostIsInstalled: runtime.isInstalled(),
            installationError: runtime.installationError,
            policy: runtime.coordinator.policy(at: date),
            canBeginBreak: runtime.coordinator.canBeginBreak,
            now: date
        )
    }

    private static func isFresh(_ date: Date, at now: Date) -> Bool {
        date <= now.addingTimeInterval(5) && now.timeIntervalSince(date) <= 60
    }

    private static func fiveSecondHealthUpdates(
        now: @escaping () -> Date
    ) -> AsyncStream<Date> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        return
                    }
                    continuation.yield(now())
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
