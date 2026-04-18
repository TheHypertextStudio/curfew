import SwiftUI

/// Advanced/diagnostic panel extensions on `SettingsView`.
extension SettingsView {
    /// Advanced/diagnostic panel — weekly reset-day picker and Streamable
    /// HTTP MCP transport toggle.
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

            Divider()

            Toggle(
                "Expose MCP over localhost HTTP",
                isOn: $model.settings.mcpHTTPEnabled
            )

            if model.settings.mcpHTTPEnabled {
                HStack {
                    Text("Port")
                        .font(CurfewTypography.body(13))
                    TextField(
                        "9847",
                        value: $model.settings.mcpHTTPPort,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }

            Text(
                "Binds to 127.0.0.1 only — never exposed on the network. " +
                    "Enable only if you're using a remote MCP client that " +
                    "can't spawn curfew-mcp over stdio. Restart Curfew to " +
                    "apply."
            )
            .font(CurfewTypography.body(12))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Re-entry point to the first-run onboarding flow. Shows a "Complete
    /// Setup" button when onboarding was not finished — enforcement is
    /// disarmed until `hasCompletedInitialSetup` is true.
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
