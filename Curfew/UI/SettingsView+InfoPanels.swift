import SwiftUI

/// Informational / configuration panels for Settings tabs that don't drive
/// enforcement directly: Integrations, Devices, Advanced, and the setup
/// re-entry panel.
extension SettingsView {
    /// Read-only status panel enumerating the deferred modules and whether
    /// each is currently enabled via ``FeatureFlags``. Clicking a
    /// disabled row is a no-op in v0.1 — turning modules on is a code
    /// change until we wire in user-facing toggles post-v0.2.
    var integrationsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Integrations",
                subtitle: "Optional modules for cloud sync, widgets, and external tooling."
            )

            integrationStatusRow(
                title: "WidgetKit",
                isEnabled: model.featureFlags.widgetKitEnabled
            )
            integrationStatusRow(
                title: "Cloud Sync",
                isEnabled: model.featureFlags.cloudSyncEnabled
            )
            integrationStatusRow(
                title: "MCP Server",
                isEnabled: model.featureFlags.mcpServerEnabled
            )
            integrationStatusRow(
                title: "Privileged Helper",
                isEnabled: model.featureFlags.privilegedHelperEnabled
            )
        }
    }

    /// Minimal single-device summary plus a count of override events
    /// logged locally. Multi-device listing comes with CloudKit sync.
    var devicesPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Devices",
                subtitle: "Current device and local override activity."
            )

            let deviceName = Host.current().localizedName
                ?? Host.current().name
                ?? "Unknown"
            Text("Current device: \(deviceName)")
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.ink)

            Text("Override events logged locally: \(model.overrideEvents.count)")
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
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
