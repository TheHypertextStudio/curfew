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
    /// Enforcement tuning (warning intervals, auto-shutdown, extension /
    /// override budgets).
    case enforcement

    /// Third-party integrations — MCP config copy, Claude Desktop
    /// auto-detect, CLI install instructions.
    case integrations

    /// Multi-device sync status and per-device activity (Pro).
    case devices

    /// Morning / evening reflection gate prompts and toggles.
    case reflection

    /// Advanced / power-user options, debug panels, feature flags.
    case advanced

    /// `Identifiable` conformance — raw string is already unique.
    var id: String {
        rawValue
    }

    /// Tab label displayed in the Settings toolbar / sidebar.
    var title: String {
        switch self {
        case .enforcement: "Enforcement"
        case .integrations: "Integrations"
        case .devices: "Devices"
        case .reflection: "Reflection"
        case .advanced: "Advanced"
        }
    }

    /// SF Symbol name for the tab icon.
    var icon: String {
        switch self {
        case .enforcement: "timer"
        case .integrations: "puzzlepiece.extension"
        case .devices: "macbook.and.iphone"
        case .reflection: "book.closed"
        case .advanced: "gearshape.2"
        }
    }
}
