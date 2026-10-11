import CurfewKit
import Foundation

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

    /// Preference, connection health, and active work are separate facts. Never
    /// describe a checked preference as proof that Chrome is currently limited.
    var statusSummary: String {
        if !enforcementEnabled {
            return "Website limits are off."
        }
        if !docketAuthorization.isHealthy {
            return "Connect Docket to use website limits."
        }
        if !docketPoll
            .isHealthy {
            return "Docket isn't responding. Check your connection to Docket."
        }
        if !nativeHost
            .isHealthy {
            return "The Chrome connection needs attention. Check connection details below."
        }
        if !extensionHeartbeat.isHealthy {
            return "Open Chrome and check that the Curfew extension is enabled."
        }
        if breakEndsAt != nil {
            return "Website limits are paused for your break."
        }
        return activeTaskTitle == nil
            ? "Waiting for an active Docket task."
            : "Ready to limit Chrome to websites for your active task."
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
