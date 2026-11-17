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

    // MARK: - Time card

    /// The year time card's fixed colours. The card draws in these in either
    /// appearance; its night stock and paper stage come from the chosen sky.
    enum TimeCard {
        /// Words on the card's sky.
        static let onSky = Color(red: 1, green: 0.965, blue: 0.918)
        /// Print on the night stock.
        static let nightPrint = Color(red: 1, green: 0.953, blue: 0.886)
        /// The pale stage under night stock.
        static let table = Color(red: 0.914, green: 0.890, blue: 0.847)
        static let nightHoleShadow = Color(red: 0.16, green: 0.12, blue: 0.10).opacity(0.28)
        static let nightShadow = Color(red: 0.10, green: 0.08, blue: 0.22).opacity(0.34)
        /// The cream paper stock and its edge.
        static let paper = HorizonRGB(0.957, 0.929, 0.875)
        static let paperEdge = Color(red: 0.886, green: 0.847, blue: 0.769)
        /// The dark ink the paper stock's print leans toward.
        static let paperInk = HorizonRGB(0.18, 0.165, 0.29)

        /// A sky colour as a SwiftUI colour.
        static func color(_ rgb: HorizonRGB) -> Color {
            Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }
}
