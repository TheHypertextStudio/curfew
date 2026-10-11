import CurfewKit
import Foundation

/// Task-based Settings destinations. Legacy raw values remain stable.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case enforcement
    case warnings
    case integrations
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "General"
        case .enforcement: "Limits"
        case .warnings: "Warnings"
        case .integrations: "Connections"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .enforcement: "hourglass"
        case .warnings: "bell"
        case .integrations: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}
