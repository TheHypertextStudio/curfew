import SwiftUI

/// Root of the Settings window. Uses a native macOS `TabView` so SwiftUI
/// renders the standard icon-toolbar tab picker at the top of the window.
///
/// Per-section panel definitions live in `SettingsView+SchedulePanels`,
/// `+EnforcementPanels`, and `+InfoPanels`. Adding a tab means (a) adding
/// a case to ``SettingsSection``, (b) adding a tab item below, and (c)
/// putting panels in the appropriate extension file.
struct SettingsView: View {
    @EnvironmentObject var model: CurfewAppModel

    var body: some View {
        TabView {
            tab {
                presetsPanel
                weeklySchedulePanel
                if let pending = model.pendingScheduleDescription {
                    pendingChangePanel(message: pending)
                }
            }
            .tabItem { Label(SettingsSection.schedule.title,
                             systemImage: SettingsSection.schedule.icon) }

            tab {
                extensionsPanel
                warningPanel
                shutdownPanel
            }
            .tabItem { Label(SettingsSection.enforcement.title,
                             systemImage: SettingsSection.enforcement.icon) }

            tab { integrationsPanel }
                .tabItem { Label(SettingsSection.integrations.title,
                                 systemImage: SettingsSection.integrations.icon) }

            tab { devicesPanel }
                .tabItem { Label(SettingsSection.devices.title,
                                 systemImage: SettingsSection.devices.icon) }

            tab {
                advancedPanel
                setupPanel
            }
            .tabItem { Label(SettingsSection.advanced.title,
                             systemImage: SettingsSection.advanced.icon) }
        }
        .tint(CurfewTheme.accent)
    }

    private func tab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }
}
