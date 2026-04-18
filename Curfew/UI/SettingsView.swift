import SwiftUI

/// Root of the Settings window.
///
/// `tabbed: true` (default) — used by the `Settings` scene; SwiftUI renders
/// a native macOS icon-toolbar tab picker at the top of the window.
/// `tabbed: false` — used when embedded inside the main workspace window's
/// Configuration pane, where a tab bar would be redundant with the outer
/// sidebar navigation. All panels are shown in a single flat scroll instead.
struct SettingsView: View {
    /// Live app state shared across panels.
    @EnvironmentObject var model: CurfewAppModel
    /// Whether to render the icon-toolbar tab picker (standalone Settings
    /// window) or a single flat scroll (embedded in the main workspace).
    var tabbed: Bool = true

    /// Dispatches to the tabbed or flat layout.
    var body: some View {
        if tabbed {
            tabbedBody
        } else {
            flatBody
        }
    }

    // MARK: - Tabbed (standalone Settings window)

    private var tabbedBody: some View {
        TabView {
            tab {
                presetsPanel
                weeklySchedulePanel
                if let pending = model.pendingScheduleDescription {
                    pendingChangePanel(message: pending)
                }
            }
            .tabItem { Label(
                SettingsSection.schedule.title,
                systemImage: SettingsSection.schedule.icon
            ) }

            tab {
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

    // MARK: - Flat (embedded in workspace Configuration pane)

    private var flatBody: some View {
        tab {
            presetsPanel
            weeklySchedulePanel
            if let pending = model.pendingScheduleDescription {
                pendingChangePanel(message: pending)
            }
            extensionsPanel
            warningPanel
            shutdownPanel
            integrationsPanel
            licensePanel
            advancedPanel
            setupPanel
            uninstallPanel
        }
        .tint(CurfewTheme.accent)
    }

    // MARK: - Shared scroll wrapper

    /// Wraps a panel's content in the shared scroll + padding treatment
    /// used by every Settings tab. Centralising it keeps the individual
    /// tab bodies terse and visually consistent.
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
