import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The single source of truth for Curfew's warm "paper + ember" identity and
/// the text roles over the sky. The sky's own colours live in
/// `HorizonPalette` (see `CurfewTheme`, `JournalPalette`, `HorizonSkyView`).
enum SundownPalette {
    // MARK: - Brand constants

    /// The warm page the workspace sanctuary sits on.
    static let paper = CurfewTheme.canvas
    /// Near-white with a warm cast — text over the dark sky.
    static let warmWhite = AtmospherePalette.warmWhite
    /// Supporting text on opaque night panels and dark reflection inputs.
    static let supportingText = warmWhite.opacity(0.82)

    /// Dark reflection inputs preserve text contrast even over the brightest sky.
    static func inputSurface(usesSolidPanels: Bool) -> Color {
        usesSolidPanels ? .black : .black.opacity(0.72)
    }

    /// Shields small atmospheric text even when the sky or page fade is white.
    /// Shares the same contrast-tested backing as reflection and override inputs.
    static let textScrim = AtmospherePalette.textScrim

    /// Primary warm near-black ink.
    static let ink = CurfewTheme.ink
    /// Secondary ink.
    static let inkSoft = CurfewTheme.mutedInk
    /// The setting sun — the one brand accent.
    static let ember = CurfewTheme.accentFill
    /// A brighter ember for kindled / pressed states.
    static let emberBright = CurfewTheme.accent
    /// A deeper ember for a filled button over the sky: dark enough that warm
    /// white reads on it at 4.5 to 1 (`SetupSkyContrastTests`).
    static let emberDeep = Color(red: 0.749, green: 0.294, blue: 0.110)
    /// Warm bloom used for the sun's glow.
    static let glow = Color(red: 1.0, green: 0.85, blue: 0.62)

    /// Shared opaque night surface for warning notices and static lock views:
    /// the Horizon night's far sky.
    static let nightSky = Color(
        red: HorizonPalette.standard.night[0].red, green: HorizonPalette.standard.night[0].green,
        blue: HorizonPalette.standard.night[0].blue
    )

    /// Solid stand-in for glass over the sky under Reduce Transparency: the
    /// Horizon night's second stop.
    static let nightPanel = Color(
        red: HorizonPalette.standard.night[1].red, green: HorizonPalette.standard.night[1].green,
        blue: HorizonPalette.standard.night[1].blue
    )
}
