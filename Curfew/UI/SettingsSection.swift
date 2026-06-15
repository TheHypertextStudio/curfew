import Foundation

/// One tab of the Settings window.
///
/// The `rawValue` is the stable identifier persisted across app versions
/// (e.g. if we add deep-link support for `curfew://settings/integrations`)
/// and also drives `Identifiable` for SwiftUI. The `title` is the display
/// label shown in the sidebar.
///
/// Ordering matters — cases appear in the sidebar in declaration order.
enum SettingsSection: String, CaseIterable, Identifiable {
    /// Enforcement tuning — extension / override budgets and their weekly
    /// reset, warning intervals, auto-shutdown.
    case enforcement

    /// Connections to the world outside Curfew — MCP control plane, AI consent,
    /// calendar, widgets, the privileged helper, and devices / iCloud sync.
    case integrations

    /// Power-user diagnostics (MCP-over-HTTP transport) and the destructive
    /// uninstall action.
    case advanced

    /// App identity and licensing — version, Curfew Pro activation, and the
    /// Getting Started re-entry.
    case about

    /// `Identifiable` conformance — raw string is already unique.
    var id: String {
        rawValue
    }

    /// Tab label displayed in the Settings toolbar / sidebar.
    var title: String {
        switch self {
        case .enforcement: "Enforcement"
        case .integrations: "Integrations"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// SF Symbol name for the tab icon.
    var icon: String {
        switch self {
        case .enforcement: "timer"
        case .integrations: "puzzlepiece.extension"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}
