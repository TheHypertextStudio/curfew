import CurfewAtmosphere
import CurfewKit
import Foundation
import SwiftUI

/// The card stock: dark with light print, or cream with dark print.
enum JournalTimeCardStock: String, CaseIterable, Codable, Sendable {
    case night
    case paper

    var title: String {
        switch self {
        case .night: "Night"
        case .paper: "Paper"
        }
    }
}

/// The sky over the card, one of the app's three palettes.
enum JournalTimeCardSky: String, CaseIterable, Codable, Sendable {
    case sundown
    case desert
    case polar

    /// The app's current sky, from the palette the theme draws in.
    init(palette: HorizonPalette) {
        switch palette {
        case .desert: self = .desert
        case .polar: self = .polar
        default: self = .sundown
        }
    }

    var palette: HorizonPalette {
        switch self {
        case .sundown: .standard
        case .desert: .desert
        case .polar: .polar
        }
    }

    var title: String {
        switch self {
        case .sundown: "Sundown"
        case .desert: "Desert"
        case .polar: "Polar"
        }
    }
}

/// What the card punches into its stock.
enum JournalTimeCardPunches: String, CaseIterable, Codable, Sendable {
    case calendar
    case skyline

    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .skyline: "Skyline"
        }
    }
}

/// The one figure on the sky.
enum JournalTimeCardHeadline: String, CaseIterable, Codable, Sendable {
    case eveningsOut
    case usualTime
    case longestRun

    var title: String {
        switch self {
        case .eveningsOut: "Evenings out"
        case .usualTime: "Usual time"
        case .longestRun: "Longest run"
        }
    }
}

/// One complete card: every choice made.
struct JournalTimeCardStyle: Equatable, Hashable, Sendable {
    var stock: JournalTimeCardStock
    var sky: JournalTimeCardSky
    var punches: JournalTimeCardPunches
    var headline: JournalTimeCardHeadline
}

/// What the person chose. A choice left unmade follows the app: the stock
/// follows the appearance and the sky follows the theme until picked.
struct JournalTimeCardChoices: Codable, Equatable, Sendable {
    var stock: JournalTimeCardStock?
    var sky: JournalTimeCardSky?
    var punches: JournalTimeCardPunches?
    var headline: JournalTimeCardHeadline?

    func resolved(colorScheme: ColorScheme, appSky: JournalTimeCardSky) -> JournalTimeCardStyle {
        JournalTimeCardStyle(
            stock: stock ?? (colorScheme == .dark ? .night : .paper),
            sky: sky ?? appSky,
            punches: punches ?? .calendar,
            headline: headline ?? .eveningsOut
        )
    }

    /// A random card that differs from `current`, with every choice made.
    static func shuffled(
        from current: JournalTimeCardStyle,
        using generator: inout some RandomNumberGenerator
    ) -> JournalTimeCardChoices {
        var style = current
        while style == current {
            style = JournalTimeCardStyle(
                stock: JournalTimeCardStock.allCases.randomElement(using: &generator) ?? .night,
                sky: JournalTimeCardSky.allCases.randomElement(using: &generator) ?? .sundown,
                punches: JournalTimeCardPunches.allCases
                    .randomElement(using: &generator) ?? .calendar,
                headline: JournalTimeCardHeadline.allCases.randomElement(using: &generator)
                    ?? .eveningsOut
            )
        }
        return JournalTimeCardChoices(
            stock: style.stock, sky: style.sky, punches: style.punches, headline: style.headline
        )
    }
}

/// Keeps the person's time card choices between launches.
struct JournalTimeCardStore: Sendable {
    static let key = "journal.timeCard.choices"

    nonisolated(unsafe) let defaults: UserDefaults

    func load() -> JournalTimeCardChoices {
        guard let data = defaults.data(forKey: Self.key),
              let choices = try? JSONDecoder().decode(JournalTimeCardChoices.self, from: data)
        else { return JournalTimeCardChoices() }
        return choices
    }

    func save(_ choices: JournalTimeCardChoices) {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The app's own preferences.
    static var standard: JournalTimeCardStore {
        JournalTimeCardStore(defaults: SharedPaths.preferences)
    }
}

extension EnvironmentValues {
    /// Where the time card keeps its choices. Snapshots and previews pass a
    /// throwaway store so they never touch the person's preferences.
    @Entry var journalTimeCardStore: JournalTimeCardStore = .standard
}
