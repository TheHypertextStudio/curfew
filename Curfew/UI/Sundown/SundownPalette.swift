import SwiftUI

/// The single source of truth for Curfew's warm "paper + ember" identity and
/// for the living sky's gradient keyframes. Every atmospheric surface and the
/// warm chrome tones derive from here, so the app can never drift into looking
/// like two apps (see `CurfewTheme`, `JournalPalette`, `SundownSky`).
enum SundownPalette {
    // MARK: - Brand constants

    /// The warm page the workspace sanctuary sits on.
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.90)
    /// Near-white with a warm cast — text over the dark sky.
    static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
    /// Primary warm near-black ink.
    static let ink = Color(red: 0.19, green: 0.16, blue: 0.14)
    /// Secondary ink.
    static let inkSoft = Color(red: 0.52, green: 0.46, blue: 0.41)
    /// The setting sun — the one brand accent.
    static let ember = Color(red: 0.85, green: 0.45, blue: 0.23)
    /// A brighter ember for kindled / pressed states.
    static let emberBright = Color(red: 0.96, green: 0.56, blue: 0.31)
    /// Warm bloom used for the sun's glow.
    static let glow = Color(red: 1.0, green: 0.85, blue: 0.62)

    // MARK: - Sky keyframes

    /// Blended four-stop gradient for a given `light` level (0 night → 1 day).
    /// Interpolates between the named keyframes so the sky changes continuously
    /// as the moment evolves rather than snapping between presets.
    static func skyStops(for light: Double) -> [Gradient.Stop] {
        let frame = blendedKeyframe(for: light)
        return zip(frame, stopLocations).map { Gradient.Stop(color: $0.color, location: $1) }
    }

    /// The sun/ember glow colour, warming toward deep ember as the lock time
    /// nears (`proximity` 0 → 1).
    static func glowColor(proximity: Double) -> Color {
        SkyRGB.glowWarm.lerp(to: .glowEmber, min(max(proximity, 0), 1)).color
    }

    // MARK: - Keyframe data

    /// Fixed stop positions, dark crown → warm horizon.
    private static let stopLocations: [Double] = [0, 0.45, 0.8, 1.0]

    /// `(light level, four stops)` keyframes, ascending. `light` selects and
    /// blends the two bracketing frames.
    private static let keyframes: [(level: Double, stops: [SkyRGB])] = [
        (0.10, night),
        (0.46, dusk),
        (0.66, golden),
        (0.95, day)
    ]

    private static let night = [
        SkyRGB(0.06, 0.07, 0.15),
        SkyRGB(0.13, 0.13, 0.23),
        SkyRGB(0.26, 0.17, 0.27),
        SkyRGB(0.42, 0.23, 0.22)
    ]
    private static let dusk = [
        SkyRGB(0.22, 0.23, 0.34),
        SkyRGB(0.42, 0.34, 0.42),
        SkyRGB(0.66, 0.42, 0.40),
        SkyRGB(0.92, 0.56, 0.34)
    ]
    private static let golden = [
        SkyRGB(0.30, 0.32, 0.42),
        SkyRGB(0.50, 0.44, 0.48),
        SkyRGB(0.78, 0.62, 0.50),
        SkyRGB(0.95, 0.82, 0.64)
    ]
    private static let day = [
        SkyRGB(0.40, 0.52, 0.70),
        SkyRGB(0.62, 0.62, 0.64),
        SkyRGB(0.82, 0.74, 0.62),
        SkyRGB(0.95, 0.86, 0.70)
    ]

    /// Picks and linearly blends the two keyframes bracketing `light`.
    private static func blendedKeyframe(for light: Double) -> [SkyRGB] {
        if light <= keyframes[0].level {
            return keyframes[0].stops
        }
        if light >= keyframes[keyframes.count - 1].level {
            return keyframes[keyframes.count - 1].stops
        }
        for index in 1 ..< keyframes.count where light <= keyframes[index].level {
            let lower = keyframes[index - 1]
            let upper = keyframes[index]
            let frac = (light - lower.level) / (upper.level - lower.level)
            return zip(lower.stops, upper.stops).map { $0.lerp(to: $1, frac) }
        }
        return keyframes[keyframes.count - 1].stops
    }
}

/// A plain RGB triple with linear interpolation, used to blend gradient
/// keyframes off the SwiftUI render path (`Color` doesn't expose components
/// portably).
private struct SkyRGB {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Component-wise lerp toward `other` by `frac` (0...1).
    func lerp(to other: SkyRGB, _ frac: Double) -> SkyRGB {
        SkyRGB(
            red + (other.red - red) * frac,
            green + (other.green - green) * frac,
            blue + (other.blue - blue) * frac
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    /// Glow endpoints for `SundownPalette.glowColor(proximity:)`.
    static let glowWarm = SkyRGB(1.0, 0.85, 0.62)
    static let glowEmber = SkyRGB(0.97, 0.46, 0.26)
}
