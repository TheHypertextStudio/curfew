import CurfewKit
import Foundation

/// Task-based Settings destinations. Legacy raw values remain stable.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case enforcement
    case warnings
    case restScreen
    case integrations
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "Protection"
        case .enforcement: "Limits"
        case .warnings: "Warnings"
        case .restScreen: "Rest Screen"
        case .integrations: "Connections"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "shield.lefthalf.filled"
        case .enforcement: "hourglass"
        case .warnings: "bell"
        case .restScreen: "moon.stars"
        case .integrations: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}
