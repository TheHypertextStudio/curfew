import SwiftUI

/// Advanced diagnostics and the Getting Started re-entry, as panel extensions
/// on `SettingsView`.
extension SettingsView {
    /// Advanced/diagnostic panel — the Streamable HTTP MCP transport toggle.
    /// The explanatory caveat sits above the control so the panel reads
    /// top-down rather than burying the "why" beneath the switch.
    var advancedPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "MCP Transport",
                subtitle: "A diagnostic for advanced MCP client setups."
            )

            Text(
                "Binds to 127.0.0.1 only — never exposed on the network. " +
                    "Enable only if you're using a remote MCP client that " +
                    "can't spawn curfew-mcp over stdio. Restart Curfew to " +
                    "apply."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)

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
