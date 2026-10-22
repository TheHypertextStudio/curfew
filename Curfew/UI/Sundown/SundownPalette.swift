import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The single source of truth for Curfew's warm "paper + ember" identity and
/// for the living sky's gradient keyframes. Every atmospheric surface and the
/// warm chrome tones derive from here, so the app can never drift into looking
/// like two apps (see `CurfewTheme`, `JournalPalette`, `SundownSky`).
enum SundownPalette {
    // MARK: - Brand constants

    /// The warm page the workspace sanctuary sits on.
    static let paper = CurfewTheme.canvas
    /// Near-white with a warm cast — text over the dark sky.
    static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
    /// Supporting text on opaque night panels and dark reflection inputs.
    static let supportingText = warmWhite.opacity(0.82)

    /// Dark reflection inputs preserve text contrast even over the brightest sky.
    static func inputSurface(usesSolidPanels: Bool) -> Color {
        usesSolidPanels ? .black : .black.opacity(0.72)
    }

    /// Shields small atmospheric text even when the sky or page fade is white.
    /// Shares the same contrast-tested backing as reflection and override inputs.
    static let textScrim = inputSurface(usesSolidPanels: false)

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

    /// Shared opaque night surface for warning capsules and static lockout views.
    static var nightSky: LinearGradient {
        LinearGradient(stops: skyStops(for: 0), startPoint: .top, endPoint: .bottom)
    }

    static func skyStops(for light: Double) -> [Gradient.Stop] {
        AtmospherePalette.skyStops(for: light)
    }

    static func glowColor(proximity: Double) -> Color {
        AtmospherePalette.glowColor(proximity: proximity)
    }

    static func skyMesh(light: Double, proximity: Double, drift: Double = 0) -> SkyMesh {
        AtmospherePalette.skyMesh(light: light, proximity: proximity, drift: drift)
    }
}

typealias SkyMesh = AtmosphereMesh
