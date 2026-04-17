import SwiftUI

/// Root of the Settings window. Shows a sidebar of `SettingsSection`
/// tabs along the top and swaps the panel stack below based on the user's
/// selection.
///
/// The per-section panel definitions live in `SettingsView+SchedulePanels`,
/// `+EnforcementPanels`, and `+InfoPanels` so this file stays focused on
/// selection + layout. Adding a new settings tab means (a) appending a
/// case to ``SettingsSection`` and (b) routing to it in `sectionContent`;
/// the panel itself can live in whichever extension file matches its
/// responsibility (or its own file if it stands alone).
struct SettingsView: View {
    /// Shared app model. Every panel reads and writes through this single
    /// source of truth — there is no per-panel state store.
    @EnvironmentObject var model: CurfewAppModel

    /// Currently selected tab. `@State` rather than persisted because
    /// "which tab was open" is an ephemeral UI concern, not a setting.
    @State var selectedSection: SettingsSection = .schedule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionSelector
                sectionContent
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(CurfewTheme.canvas)
        .tint(CurfewTheme.accent)
        .foregroundStyle(CurfewTheme.ink)
    }

    /// Top-of-window tab bar — one button per `SettingsSection`.
    private var settingsSectionSelector: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Settings",
                subtitle: "Choose a section to configure Curfew."
            )

            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    if selectedSection == section {
                        Button(section.title) {
                            selectedSection = section
                        }
                        .buttonStyle(CurfewPrimaryButtonStyle())
                    } else {
                        Button(section.title) {
                            selectedSection = section
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    /// Dispatches the selected section to the appropriate panel stack.
    /// Each branch is a thin wrapper around panels defined in sibling
    /// `SettingsView+*` extension files.
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .schedule:
            presetsPanel
            weeklySchedulePanel
            if let pending = model.pendingScheduleDescription {
                pendingChangePanel(message: pending)
            }
        case .enforcement:
            extensionsPanel
            warningPanel
            shutdownPanel
        case .integrations:
            integrationsPanel
        case .devices:
            devicesPanel
        case .advanced:
            advancedPanel
            setupPanel
        }
    }
}
