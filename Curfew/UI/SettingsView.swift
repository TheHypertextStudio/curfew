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

    /// The selected tab. Bound so panels can navigate between tabs — e.g. the
    /// Reflection panel's "Set up in Integrations" callout jumps here.
    @State var selection: SettingsSection = .enforcement

    /// Which reflection prompt's text field should hold keyboard focus —
    /// driven so "Add prompt" focuses the freshly-added row.
    @FocusState var focusedPromptID: UUID?

    /// Tabbed settings layout.
    var body: some View {
        TabView(selection: $selection) {
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
            .tag(SettingsSection.enforcement)

            tab { integrationsPanel }
                .tabItem { Label(
                    SettingsSection.integrations.title,
                    systemImage: SettingsSection.integrations.icon
                ) }
                .tag(SettingsSection.integrations)

            tab { devicesPanel }
                .tabItem { Label(
                    SettingsSection.devices.title,
                    systemImage: SettingsSection.devices.icon
                ) }
                .tag(SettingsSection.devices)

            tab { reflectionPanel }
                .tabItem { Label(
                    SettingsSection.reflection.title,
                    systemImage: SettingsSection.reflection.icon
                ) }
                .tag(SettingsSection.reflection)

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
            .tag(SettingsSection.advanced)
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
