import SwiftUI

/// Root of the Settings window — the home for system and enforcement
/// configuration (⌘,).
///
/// Renders a native macOS icon-toolbar tab picker. Two things are deliberately
/// *not* here, because they're core acts rather than buried settings: the
/// schedule editor (promoted to the `Schedule` workspace destination, see
/// ``ScheduleView``) and the reflection prompt editor (promoted to the Reflect
/// destination, see ``ReflectionPromptsView``).
struct SettingsView: View {
    /// Live app state shared across panels.
    @EnvironmentObject var model: CurfewAppModel

    /// The selected tab. Held as state so the window restores the last tab and
    /// callouts can navigate between tabs if needed.
    @State var selection: SettingsSection = .enforcement

    /// Tabbed settings layout.
    var body: some View {
        TabView(selection: $selection) {
            tab {
                enforcementHealthPanel
                extensionsPanel
                warningPanel
                presencePanel
                shutdownPanel
                protectedWorkPanel
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

            tab {
                advancedPanel
                uninstallPanel
            }
            .tabItem { Label(
                SettingsSection.advanced.title,
                systemImage: SettingsSection.advanced.icon
            ) }
            .tag(SettingsSection.advanced)

            tab { aboutPanel }
                .tabItem { Label(
                    SettingsSection.about.title,
                    systemImage: SettingsSection.about.icon
                ) }
                .tag(SettingsSection.about)
        }
        .tint(CurfewTheme.accent)
    }

    /// Wraps a panel's content in the shared scroll + padding treatment used
    /// by every Settings tab. Centralising it keeps the individual tab bodies
    /// terse and visually consistent. Panels are separated by
    /// `CurfewSpacing.section` — wider than the intra-panel `md` gap — so each
    /// card reads as a distinct group.
    func tab(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurfewSpacing.section) {
                content()
            }
            .padding(CurfewSpacing.xLarge)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }
}
