import CurfewKit
import EventKit
import ServiceManagement
import SwiftUI

/// Informational / configuration panels for Settings tabs that don't drive
/// enforcement directly: Integrations, Devices, Advanced, and the setup
/// re-entry panel.
extension SettingsView {
    /// Integrations panel: MCP server setup, Claude Desktop config snippet,
    /// and AI consent policy picker.
    var integrationsPanel: some View {
        VStack(spacing: CurfewSpacing.section) {
            mcpConfigPanel
            aiConsentPanel
            otherIntegrationsPanel
            devicesPanel
        }
    }

    /// MCP server setup + Claude Desktop config. Gated on
    /// `featureFlags.mcpServerEnabled` so a build that doesn't ship the MCP
    /// control plane hides the toggle and the "Configure Claude Desktop"
    /// button entirely — they can't surface a runtime the app never starts.
    /// `settings.mcpEnabled` only gates the runtime when the flag is on too.
    @ViewBuilder
    private var mcpConfigPanel: some View {
        if model.featureFlags.mcpServerEnabled {
            enabledMCPConfigPanel
        }
    }

    private var enabledMCPConfigPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "MCP Control Plane",
                subtitle: "Allow AI assistants to control your device"
                    + " via the Model Context Protocol."
            )

            Toggle("Enable MCP Control Plane", isOn: $model.settings.mcpEnabled)

            Text(
                "When enabled, AI assistants can lock and unlock your device, "
                    + "request time extensions, and manage Curfew settings. They can "
                    + "also read your status, schedule, and daily reflections (your "
                    + "journal stays on this Mac — it's never uploaded). "
                    + "Only enable if you trust the AI clients you're connecting."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)

            if model.settings.mcpEnabled {
                Text("""
                `curfew-mcp` is a stdio MCP server bundled with Curfew. Add it to \
                Claude Desktop (or any MCP host) by pasting the config snippet below \
                into your `claude_desktop_config.json` under `mcpServers`.
                """)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Copy Claude Desktop Config") {
                        copyClaudeDesktopConfig()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())

                    claudeDesktopRegisterButton
                }

                if !model.pendingMCPRequests.isEmpty {
                    HStack(spacing: 8) {
                        Text("\(model.pendingMCPRequests.count) pending AI request(s)")
                            .font(CurfewTypography.bodyEmphasis(13))
                            .foregroundStyle(CurfewTheme.accent)
                        Button("Review") {
                            model.openSettings()
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    /// AI consent policy picker.
    private var aiConsentPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "AI Consent Policy",
                subtitle: "Choose how Curfew handles AI-requested changes."
            )

            Picker("Policy", selection: $model.aiConsentPolicy) {
                ForEach(AIConsentPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy)
                }
            }
            .pickerStyle(.radioGroup)

            Text(model.aiConsentPolicy.rationale)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    /// Read-only status panel for deferred non-MCP modules.
    private var otherIntegrationsPanel: some View {
        VStack(spacing: CurfewSpacing.section) {
            if DeferredFeaturePanel.visible(for: model.featureFlags).isEmpty {
                CurfewPanel {
                    CurfewSectionTitle(
                        title: "Additional Integrations",
                        subtitle: "This build only ships MCP-driven integrations."
                    )
                    Text(
                        "WidgetKit, Calendar, Cloud Sync, and the privileged helper "
                            + "are hidden until they are enabled for the current build."
                    )
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.featureFlags.widgetKitEnabled {
                ProGate(
                    feature: "WidgetKit",
                    description: "See your enforcement phase and time remaining at a glance."
                ) {
                    CurfewPanel {
                        CurfewSectionTitle(
                            title: "WidgetKit",
                            subtitle: "Small, medium, and large widgets."
                        )
                        integrationStatusRow(
                            title: "WidgetKit",
                            isEnabled: true
                        )
                    }
                }
                .environmentObject(model)
            }
            if model.featureFlags.calendarEnabled {
                ProGate(
                    feature: "Calendar",
                    description: "See today's scheduled events on the lockout screen and in This"
                        + " Week."
                ) {
                    CurfewPanel {
                        CurfewSectionTitle(
                            title: "Calendar",
                            subtitle: "Today's events shown alongside enforcement status."
                        )
                        integrationStatusRow(
                            title: "Calendar",
                            isEnabled: true
                        )
                        calendarAuthRow
                    }
                }
                .environmentObject(model)
            }

            if model.featureFlags.privilegedHelperEnabled {
                CurfewPanel {
                    CurfewSectionTitle(
                        title: "Privileged Helper",
                        subtitle: "Root-owned daemon for stronger bypass prevention."
                    )
                    integrationStatusRow(
                        title: "Privileged Helper",
                        isEnabled: true
                    )
                    privilegedHelperPanel
                }
            }
        }
    }

    @ViewBuilder
    private var calendarAuthRow: some View {
        switch model.calendarMonitor.authorizationStatus {
        case .fullAccess:
            let count = model.calendarMonitor.todayEvents.count
            Text("Calendar access granted. \(count) event(s) today.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        case .notDetermined:
            Button("Grant Calendar Access") {
                model.calendarMonitor.requestAccessAndSync()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        default:
            Text(
                "Calendar access denied. Open System Settings → Privacy → Calendars to enable."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Copies a ready-to-paste Claude Desktop MCP config JSON snippet for
    /// `curfew-mcp` to the clipboard.
    private func copyClaudeDesktopConfig() {
        let executablePath = Bundle.main.bundlePath +
            "/Contents/Resources/curfew-mcp"
        let config = """
        {
          "mcpServers": {
            "curfew": {
              "command": "\(executablePath)",
              "args": []
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }

    /// Cross-device overview. Pairs the live `DeviceRegistry` list with
    /// the Pro cloud-sync panel so users can see sync health in one
    /// place. Before Pro is unlocked the list is just the local Mac.
    var devicesPanel: some View {
        VStack(spacing: CurfewSpacing.section) {
            devicesListPanel

            CurfewPanel {
                CurfewSectionTitle(
                    title: "This Device",
                    subtitle: "Local overrides and activity."
                )
                Text("Override events logged locally: \(model.overrideEvents.count)")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            if model.featureFlags.cloudSyncEnabled {
                ProGate(
                    feature: "Cloud Sync",
                    description: "Keep your schedule in sync across all your Macs via iCloud."
                ) {
                    cloudSyncPanel
                }
                .environmentObject(model)
            }
        }
    }

    private var cloudSyncPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "iCloud Sync",
                subtitle: "Your schedule syncs automatically across all your Macs."
            )

            integrationStatusRow(
                title: "iCloud Sync",
                isEnabled: model.featureFlags.cloudSyncEnabled
            )

            if model.featureFlags.cloudSyncEnabled {
                syncStatusRow
            } else {
                Text("Cloud sync is available but not yet provisioned. "
                    + "Provision the CloudKit container in App Store Connect "
                    + "and set cloudSyncEnabled in FeatureFlags.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Displays the current CloudKit sync status inline in the Devices panel.
    @ViewBuilder
    private var syncStatusRow: some View {
        switch model.cloudKitSyncEngine.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        case .synced(let syncDate):
            HStack {
                Text("Last synced")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                Spacer()
                Text(syncDate, style: .relative)
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        case .failed(let message):
            Text("Sync failed: \(message)")
                .font(CurfewTypography.body(13))
                .foregroundStyle(Color.red.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        case .unavailable:
            Text("iCloud unavailable. Sign in to iCloud in System Settings to enable sync.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// License key entry and Pro status panel.
    var licensePanel: some View {
        LicenseView()
            .environmentObject(model)
    }

    /// Shared row layout for the Integrations panel.
    ///
    /// - Parameters:
    ///   - title: integration display name.
    ///   - isEnabled: whether the corresponding feature flag is currently
    ///     on; drives both the trailing label and its colour.
    func integrationStatusRow(title: String, isEnabled: Bool) -> some View {
        HStack {
            Text(title)
                .font(CurfewTypography.bodyEmphasis(14))
            Spacer()
            Text(isEnabled ? "Enabled" : "Disabled")
                .font(CurfewTypography.label(12))
                .foregroundStyle(isEnabled ? CurfewTheme.accent : CurfewTheme.mutedInk)
        }
    }

    /// Install / uninstall controls for the SMAppService privileged daemon and
    /// the main-app login item. Only shown when `privilegedHelperEnabled`.
    @ViewBuilder
    private var privilegedHelperPanel: some View {
        let helper = model.privilegedHelperManager
        VStack(alignment: .leading, spacing: 10) {
            // Daemon row
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
                        helper.uninstallDaemon()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                } else {
                    Button("Install…") {
                        helper.installDaemon()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }

            // Login item row
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
        }
    }
}
