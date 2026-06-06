import SwiftUI

/// Root of the Settings window — the single configuration home (⌘,).
///
/// Renders a native macOS icon-toolbar tab picker. Note the schedule editor
/// is deliberately *not* here: it's promoted to a first-class `Schedule`
/// workspace destination (see ``ScheduleView``), because choosing your
/// horizon is the core act of the app, not a buried setting.
struct SettingsView: View {
    /// Live app state shared across panels.
    @EnvironmentObject var model: CurfewAppModel

    /// Tabbed settings layout.
    var body: some View {
        TabView {
            tab {
                enforcementHealthPanel
                extensionsPanel
                warningPanel
                shutdownPanel
            }
            .tabItem { Label(
                SettingsSection.enforcement.title,
                systemImage: SettingsSection.enforcement.icon
            ) }

            tab { integrationsPanel }
                .tabItem { Label(
                    SettingsSection.integrations.title,
                    systemImage: SettingsSection.integrations.icon
                ) }

            tab { devicesPanel }
                .tabItem { Label(
                    SettingsSection.devices.title,
                    systemImage: SettingsSection.devices.icon
                ) }

            tab {
                licensePanel
                advancedPanel
                setupPanel
                uninstallPanel
            }
            .tabItem { Label(
                SettingsSection.advanced.title,
                systemImage: SettingsSection.advanced.icon
            ) }
        }
        .tint(CurfewTheme.accent)
    }

    /// Wraps a panel's content in the shared scroll + padding treatment used
    /// by every Settings tab. Centralising it keeps the individual tab
    /// bodies terse and visually consistent.
    func tab(@ViewBuilder content: () -> some View) -> some View {
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
