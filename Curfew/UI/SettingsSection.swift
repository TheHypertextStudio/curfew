import CurfewKit
import Foundation

/// Settings destinations. Existing raw values stay stable for callers.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case enforcement
    case presence
    case shutdown
    case protectedWork
    case account
    case integrations
    case advanced
    case about

    static var warnings: Self {
        .enforcement
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: "Protection"
        case .enforcement: "Lockout"
        case .presence: "Presence"
        case .shutdown: "Shutdown"
        case .protectedWork: "Protected Work"
        case .account: "Account"
        case .integrations: "Integrations"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "shield.lefthalf.filled"
        case .enforcement: "lock"
        case .presence: "person.crop.rectangle"
        case .shutdown: "power"
        case .protectedWork: "terminal"
        case .account: "person.crop.circle"
        case .integrations: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}
