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
    /// Schedule editor (weekly lock/unlock times, day-off toggles, presets).
    case schedule

    /// Enforcement tuning (warning intervals, auto-shutdown, extension /
    /// override budgets).
    case enforcement

    /// Third-party integrations — MCP config copy, Claude Desktop
    /// auto-detect, CLI install instructions.
    case integrations

    /// Multi-device sync status and per-device activity (Pro).
    case devices

    /// Advanced / power-user options, debug panels, feature flags.
    case advanced

    var id: String {
        rawValue
    }

    /// Sidebar display label.
    var title: String {
        switch self {
        case .schedule:
            "Schedule"
        case .enforcement:
            "Enforcement"
        case .integrations:
            "Integrations"
        case .devices:
            "Devices"
        case .advanced:
            "Advanced"
        }
    }
}
