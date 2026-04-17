import SwiftUI

extension SettingsView {
    /// Advanced/diagnostic panel — weekly reset-day picker.
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
