import EventKit
import SwiftUI

/// Informational / configuration panels for Settings tabs that don't drive
/// enforcement directly: Integrations, Devices, Advanced, and the setup
/// re-entry panel.
extension SettingsView {
    /// Integrations panel: MCP server setup, Claude Desktop config snippet,
    /// and AI consent policy picker.
    var integrationsPanel: some View {
        VStack(spacing: 16) {
            mcpConfigPanel
            aiConsentPanel
            otherIntegrationsPanel
        }
    }

    /// MCP server setup instructions and Claude Desktop config copy button.
    private var mcpConfigPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "MCP Control Plane",
                subtitle: "Allow AI assistants to control your device via the Model Context Protocol."
            )

            Toggle("Enable MCP Control Plane", isOn: $model.settings.mcpEnabled)

            Text("When enabled, AI assistants can lock and unlock your device, request time extensions, and manage Curfew settings. Only enable if you trust the AI clients you're connecting.")
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

                Button("Copy Claude Desktop Config") {
                    copyClaudeDesktopConfig()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

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
        VStack(spacing: 16) {
            ProGate(
                feature: "WidgetKit",
                description: "See your enforcement phase and time remaining at a glance."
            ) {
                CurfewPanel {
                    CurfewSectionTitle(title: "WidgetKit", subtitle: "Small, medium, and large widgets.")
                    integrationStatusRow(title: "WidgetKit", isEnabled: model.featureFlags.widgetKitEnabled)
                }
            }
            .environmentObject(model)

            ProGate(
                feature: "Calendar",
                description: "See today's scheduled events on the lockout screen and in This Week."
            ) {
                CurfewPanel {
                    CurfewSectionTitle(
                        title: "Calendar",
                        subtitle: "Today's events shown alongside enforcement status."
                    )
                    integrationStatusRow(
                        title: "Calendar",
                        isEnabled: model.featureFlags.calendarEnabled
                    )
                    if model.featureFlags.calendarEnabled {
                        calendarAuthRow
                    }
                }
            }
            .environmentObject(model)

            CurfewPanel {
                CurfewSectionTitle(title: "Privileged Helper", subtitle: "Stronger bypass prevention via a root-owned helper.")
                integrationStatusRow(title: "Privileged Helper", isEnabled: model.featureFlags.privilegedHelperEnabled)
                Text("Ships in v0.2.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private var calendarAuthRow: some View {
        switch model.calendarMonitor.authorizationStatus {
        case .fullAccess:
            Text("Calendar access granted. \(model.calendarMonitor.todayEvents.count) event(s) today.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        case .notDetermined:
            Button("Grant Calendar Access") {
                model.calendarMonitor.requestAccessAndSync()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        default:
            Text("Calendar access denied. Open System Settings → Privacy → Calendars to enable.")
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

    /// Single-device summary plus the Pro cloud sync panel.
    var devicesPanel: some View {
        VStack(spacing: 16) {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "This Device",
                    subtitle: "Local schedule and activity."
                )

                let deviceName = Host.current().localizedName
                    ?? Host.current().name
                    ?? "Unknown"
                Text("Device: \(deviceName)")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.ink)

                Text("Override events logged locally: \(model.overrideEvents.count)")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            ProGate(
                feature: "Cloud Sync",
                description: "Keep your schedule in sync across all your Macs via iCloud."
            ) {
                cloudSyncPanel
            }
            .environmentObject(model)
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

            if !model.featureFlags.cloudSyncEnabled {
                Text("Cloud sync is available but not yet provisioned. "
                   + "Provision the CloudKit container in App Store Connect "
                   + "and set cloudSyncEnabled in FeatureFlags.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// License key entry and Pro status panel.
    var licensePanel: some View {
        LicenseView()
            .environmentObject(model)
    }

    /// Advanced/diagnostic panel — currently just the weekly reset-day
    /// picker. Placeholder for future debug toggles.
    var advancedPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Advanced",
                subtitle: "Fine-grained controls for weekly reset timing and diagnostics."
            )

            Picker("Weekly reset day", selection: $model.settings.resetWeekday) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

            Text("Reset day controls when extension and override budgets refresh.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
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

    /// Re-entry point to the first-run onboarding flow. Also exposes a
    /// "Complete Setup" affordance when the user ended onboarding without
    /// finishing — enforcement remains disarmed until `hasCompletedInitialSetup`
    /// is true.
    var setupPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Getting Started",
                subtitle: "Curfew is a full app with menu bar quick access."
            )

            if model.settings.hasCompletedInitialSetup {
                Text("Initial setup is complete.")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            } else {
                Button("Complete Setup and Enable Curfew") {
                    model.completeInitialSetup()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
            }

            HStack(spacing: 10) {
                Button("Show Getting Started") {
                    model.showGettingStarted()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                Button("Open Settings Window") {
                    model.openSettings()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
    }
}
