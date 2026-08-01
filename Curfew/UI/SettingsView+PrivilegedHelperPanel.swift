import CurfewKit
import ServiceManagement
import SwiftUI

extension SettingsView {
    /// Install and removal controls for the authenticated LaunchDaemon and
    /// main-app login item. Only shown when `privilegedHelperEnabled`.
    @ViewBuilder
    var privilegedHelperPanel: some View {
        let helper = model.privilegedHelperManager
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LaunchDaemon")
                        .font(CurfewTypography.bodyEmphasis(13))
                    Text(PrivilegedHelperStatusCopy.daemonDescription(for: helper.daemonStatus))
                        .font(CurfewTypography.label(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
                Spacer()
                if helper.daemonStatus == .enabled {
                    Button("Uninstall") {
                        Task { await helper.uninstallDaemon() }
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                } else {
                    Button("Install…") {
                        helper.installDaemon()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at Login")
                        .font(CurfewTypography.bodyEmphasis(13))
                    Text(PrivilegedHelperStatusCopy
                        .loginItemDescription(for: helper.loginItemStatus))
                        .font(CurfewTypography.label(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
                Spacer()
                if helper.loginItemStatus == .enabled {
                    Button("Disable") {
                        helper.unregisterLoginItem()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                } else {
                    Button("Enable") {
                        helper.registerLoginItem()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }

            if let err = helper.lastError {
                Text(err)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Authenticated channel: \(helper.connectionState.statusText)")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }
}

private extension PrivilegedHelperManager.ConnectionState {
    var statusText: String {
        switch self {
        case .ready: "Ready"
        case .unavailable: "Unavailable"
        case .unauthorized: "Rejected this app signature"
        case .stale: "Heartbeat stale"
        case .registrationFailed: "Registration failed"
        }
    }
}
