import AppKit
import CurfewKit
import ServiceManagement
import SwiftUI

/// What the Curfew helper row says and offers. The helper is presented as one
/// thing even though it is three registrations underneath (the restart
/// service, the privileged helper and the login item): the person only needs
/// to know whether curfew will hold if Curfew quits, and what to press if not.
struct CurfewHelperStatus: Equatable {
    enum Tone: Equatable {
        case ready
        case working
        case attention

        /// The row's headline; the sentence under it says the rest.
        var title: String {
            switch self {
            case .ready: "On"
            case .working: "Starting"
            case .attention: "Needs attention"
            }
        }
    }

    enum Action: Equatable {
        /// Open Login Items in System Settings so macOS can allow the helper.
        case allowInSystemSettings
        /// Register whatever is missing.
        case setUp
        /// Reconnect a registered helper that stopped answering.
        case reconnect
        /// Quit and reopen Curfew, which reconnects the helper at launch.
        case reopenCurfew

        var title: String {
            switch self {
            case .allowInSystemSettings: "Allow in System Settings…"
            case .setUp: "Set up the Curfew helper"
            case .reconnect: "Reconnect"
            case .reopenCurfew: "Quit and reopen Curfew"
            }
        }
    }

    struct Inputs: Equatable {
        var restartAvailable = true
        var restartStatus: SMAppService.Status = .enabled
        var restartHealthy = true
        var restartProblem = false
        var helperRequired = true
        var helperStatus: SMAppService.Status = .enabled
        var connection: PrivilegedHelperManager.ConnectionState = .ready
        var maintenancePaused = false
        var loginItemStatus: SMAppService.Status = .enabled
        var inProgress = false
        var isLocked = false
        var canReconnectInPlace = true
    }

    let tone: Tone
    let sentence: String
    let action: Action?

    static let readySentence = "The Curfew helper keeps curfew in place, even if Curfew quits."
    static let lockedSuffix = " You can fix this once curfew lifts."

    init(_ inputs: Inputs) {
        self = Self.registration(inputs) ?? Self.connection(inputs) ?? Self.restart(inputs)
    }

    /// Work in progress, approvals and missing registrations come first.
    private static func registration(_ inputs: Inputs) -> Self? {
        if inputs.inProgress {
            return Self(.working, "Connecting the Curfew helper…", nil)
        }
        // The restart agent's status counts only where the agent exists; the
        // login item and the helper wait for approval either way.
        let approvals = (inputs.restartAvailable ? [inputs.restartStatus] : [])
            + [inputs.loginItemStatus]
            + (inputs.helperRequired ? [inputs.helperStatus] : [])
        if approvals.contains(.requiresApproval) {
            return Self(
                .attention,
                "macOS is waiting for you to allow the Curfew helper in Login Items.",
                .allowInSystemSettings
            )
        }
        let missing = [SMAppService.Status.notRegistered, .notFound]
        let restartMissing = inputs.restartAvailable && missing.contains(inputs.restartStatus)
        let helperMissing = inputs.helperRequired && missing.contains(inputs.helperStatus)
        if restartMissing || helperMissing {
            return Self(
                .attention,
                "The Curfew helper isn't set up, so curfew only holds while Curfew is open.",
                .setUp
            )
        }
        return nil
    }

    /// A registered helper that failed to install or stopped answering.
    private static func connection(_ inputs: Inputs) -> Self? {
        guard inputs.helperRequired else { return nil }
        if inputs.connection == .registrationFailed {
            return Self(.attention, "The Curfew helper didn't finish installing.", .setUp)
        }
        guard inputs.connection != .ready || inputs.maintenancePaused else { return nil }
        let sentence = inputs.connection == .unauthorized
            ? "This Mac doesn't trust the Curfew helper right now."
            : "The Curfew helper stopped answering."
        if inputs.isLocked {
            return Self(.attention, sentence + lockedSuffix, nil)
        }
        return Self(.attention, sentence, inputs.canReconnectInPlace ? .reconnect : .reopenCurfew)
    }

    /// The restart service's own health once everything is registered.
    private static func restart(_ inputs: Inputs) -> Self {
        if inputs.restartAvailable, inputs.restartProblem {
            let sentence = "The Curfew helper stopped checking in."
            return inputs.isLocked
                ? Self(.attention, sentence + lockedSuffix, nil)
                : Self(.attention, sentence, .reopenCurfew)
        }
        if inputs.restartAvailable, !inputs.restartHealthy {
            return Self(.working, "The Curfew helper is starting.", nil)
        }
        return Self(.ready, readySentence, nil)
    }

    private init(_ tone: Tone, _ sentence: String, _ action: Action?) {
        self.tone = tone
        self.sentence = sentence
        self.action = action
    }
}

extension SettingsView {
    /// One row group for everything that keeps curfew in place while the app
    /// is closed, replacing the separate recovery, protection and login rows.
    var curfewHelperPanel: some View {
        CurfewHelperPanel(
            model: model,
            restart: model.backgroundServiceManager,
            runtimePersistenceError: model.runtimePersistenceError
        )
    }
}

private struct CurfewHelperPanel: View {
    let model: CurfewAppModel
    @ObservedObject var restart: BackgroundServiceManager
    let runtimePersistenceError: String?
    @State private var showsDetails = false

    private var helper: PrivilegedHelperManager {
        model.privilegedHelperManager
    }

    private var status: CurfewHelperStatus {
        CurfewHelperStatus(.init(
            restartAvailable: restart.isAvailable,
            restartStatus: restart.status,
            restartHealthy: restart.isRecoveryHealthy,
            restartProblem: restart.supervisorHealthError != nil || restart.lastError != nil,
            helperRequired: model.featureFlags.privilegedHelperEnabled,
            helperStatus: helper.daemonStatus,
            connection: helper.connectionState,
            maintenancePaused: helper.maintenancePaused,
            loginItemStatus: model.featureFlags.privilegedHelperEnabled
                ? helper.loginItemStatus : .enabled,
            inProgress: helper.installationInProgress || helper.repairInProgress,
            isLocked: model.state.phase == .locked,
            canReconnectInPlace: !model.isEnforcementRunning &&
                model.settings.accountSync.enrollment != nil
        ))
    }

    var body: some View {
        let status = status
        let isLocked = model.state.phase == .locked
        SettingsGroup("Curfew helper") {
            SettingsActionRow(
                title: status.tone.title,
                detail: status.sentence,
                tone: status.tone == .attention ? .warning : .secondary,
                actionTitle: status.action?.title,
                identifier: "curfew-helper-action"
            ) {
                if let action = status.action {
                    perform(action)
                }
            }
            .accessibilityIdentifier("curfew-helper-status")
            if let runtimePersistenceError {
                SettingsActionRow(
                    title: "Can't save more time and overrides",
                    detail: runtimePersistenceError,
                    tone: .warning,
                    actionTitle: nil
                )
                .accessibilityIdentifier("runtime-persistence-error")
            }
            if model.featureFlags.privilegedHelperEnabled, helper.daemonStatus == .enabled {
                DisclosureGroup(isExpanded: $showsDetails) {
                    SettingsActionRow(
                        title: "Remove the Curfew helper",
                        detail: isLocked
                            ? "The helper can't be removed while this Mac is locked."
                            : helper.lastError ?? "Your schedule and history stay saved.",
                        actionTitle: "Remove…",
                        identifier: "background-protection-remove"
                    ) {
                        Task { await helper.uninstallDaemon() }
                    }
                    .disabled(isLocked)
                } label: {
                    SettingsRowLabel(title: "Details")
                }
            }
        }
        .disabled(helper.installationInProgress || helper.repairInProgress)
        .onAppear { restart.refreshStatus() }
        .onReceive(NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                restart.refreshStatus()
        }
    }

    private func perform(_ action: CurfewHelperStatus.Action) {
        guard !model.isDemoSession else { return }
        switch action {
        case .allowInSystemSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .setUp:
            if restart.isAvailable, restart.status != .enabled {
                restart.register()
            }
            if model.featureFlags.privilegedHelperEnabled {
                if helper.loginItemStatus != .enabled {
                    helper.registerLoginItem()
                }
                if helper.daemonStatus != .enabled || helper.connectionState != .ready {
                    Task { await helper.installAndConnectDaemon() }
                }
            }
        case .reconnect:
            Task { await model.reconnectBackgroundProtection() }
        case .reopenCurfew:
            Self.reopenCurfew()
        }
    }

    /// Starts a fresh copy once this one has quit, so the single-instance
    /// guard is never contested, then quits.
    private static func reopenCurfew() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
