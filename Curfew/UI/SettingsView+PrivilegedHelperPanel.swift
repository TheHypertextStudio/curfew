import CurfewKit
import ServiceManagement
import SwiftUI

extension SettingsView {
    var privilegedHelperPanel: some View {
        let helper = model.privilegedHelperManager
        return Section {
            Toggle("Open at login", isOn: Binding(
                get: { helper.loginItemStatus == .enabled },
                set: { enabled in
                    if enabled {
                        helper.registerLoginItem()
                    } else {
                        helper.unregisterLoginItem()
                    }
                }
            ))
            if helper.loginItemStatus == .requiresApproval {
                Button("Approve in System Settings…") {
                    if !model.isDemoSession {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
            LabeledContent("Background protection") {
                if helper.installationInProgress || helper.repairInProgress {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                    }
                } else if helper.daemonStatus == .requiresApproval {
                    Button("Approve…") {
                        if !model.isDemoSession {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                } else if helper.daemonStatus == .enabled {
                    HStack {
                        Text(helper.connectionState.statusText)
                            .foregroundStyle(CurfewTheme.mutedInk)
                        if helper.connectionState != .ready || helper.maintenancePaused {
                            Button("Connect…") {
                                Task { await model.reconnectBackgroundProtection() }
                            }
                            .disabled(helper.repairInProgress || model.isEnforcementRunning)
                            .help("Turn Curfew off before reconnecting background protection.")
                        }
                    }
                } else if helper.maintenancePaused {
                    Button("Connect…") {
                        Task { await model.reconnectBackgroundProtection() }
                    }
                    .disabled(helper.repairInProgress || model.isEnforcementRunning)
                } else {
                    Button("Connect…") {
                        Task { await helper.installAndConnectDaemon() }
                    }
                }
            }
            if helper.connectionState != .ready {
                Text(
                    "Connect checks saved protection state and restores background protection. "
                        + "macOS may ask for your administrator password to verify that state."
                )
                .font(.caption)
                .foregroundStyle(CurfewTheme.mutedInk)
            }
            DisclosureGroup("Details") {
                LabeledContent(
                    "Installation",
                    value: PrivilegedHelperStatusCopy.daemonDescription(
                        for: helper.daemonStatus
                    )
                )
                LabeledContent("Connection", value: helper.connectionState.statusText)
                if helper.daemonStatus == .enabled {
                    Button("Remove Background Protection…") {
                        Task { await helper.uninstallDaemon() }
                    }
                }
            }
            if let error = helper.lastError {
                DisclosureGroup("Troubleshooting") {
                    Text(error).textSelection(.enabled)
                    Text(helper.connectionState.remediation)
                }
            }
        } header: {
            Text("Options")
        } footer: {
            Text(
                "Install with macOS approval to keep your curfew in place if the app stops."
            )
        }
        .disabled(helper.repairInProgress || helper.installationInProgress)
    }
}

private extension PrivilegedHelperManager.ConnectionState {
    var remediation: String {
        switch self {
        case .ready: "Background protection is connected."
        case .unavailable: "Install or approve background protection above."
        case .unauthorized: EnforcementHealth.degradedHelperUnauthorized.bannerDetail ?? ""
        case .stale: "Reopen Curfew to reconnect background protection."
        case .registrationFailed:
            "Try installing background protection again. "
                + "Approve it in System Settings if asked."
        }
    }

    var statusText: String {
        switch self {
        case .ready: "Connected"
        case .unavailable: "Not connected"
        case .unauthorized: EnforcementHealth.degradedHelperUnauthorized.settingsStatusTitle
        case .stale: "Connection interrupted"
        case .registrationFailed: "Installation failed"
        }
    }
}
