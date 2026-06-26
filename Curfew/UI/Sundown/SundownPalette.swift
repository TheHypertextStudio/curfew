import CurfewKit
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

    // MARK: - Mesh gradient

    /// Control points and colours for rendering the sky as a `MeshGradient`
    /// (macOS 15+), derived entirely from the same four keyframe stops the
    /// linear sky used — no new colour model. The mesh is a 3×4 grid: three
    /// columns across, four rows down sitting at the existing ``stopLocations``
    /// (dark crown → warm horizon). Every column of a row takes that row's
    /// blended keyframe stop, so straight down the centre the mesh reproduces
    /// the original vertical gradient exactly; the sun-side (right) column of
    /// the two horizon rows is warmed toward the ember ``glow`` so the sunset
    /// reads asymmetrically beneath the sun disc (which always rides the right
    /// of the sky). `drift` (a phase in radians, held at 0 under Reduce Motion)
    /// gently sways the interior control points so the sky breathes; at
    /// `drift == 0` the grid is a still, regular lattice.
    static func skyMesh(
        light: Double,
        proximity: Double,
        drift: Double = 0
    ) -> SkyMesh {
        let frame = blendedKeyframe(for: light)
        let glow = SkyRGB.glowWarm.lerp(to: .glowEmber, min(max(proximity, 0), 1))

        // Per-row base colours, dark crown → warm horizon.
        let crown = frame[0]
        let upper = frame[1]
        let lower = frame[2]
        let horizon = frame[3]

        // Warm the sun-side column of the two lowest rows toward the ember so
        // the horizon glows where the sun sits.
        let lowerWarm = lower.lerp(to: glow, 0.14)
        let horizonWarm = horizon.lerp(to: glow, 0.24)

        let colors: [Color] = [
            crown.color, crown.color, crown.color,
            upper.color, upper.color, upper.color,
            lower.color, lower.color, lowerWarm.color,
            horizon.color, horizon.color, horizonWarm.color
        ]

        // Gentle breathing of the interior control points; frozen at drift == 0.
        let sway = Float(sin(drift * 0.27) * 0.03)
        let bob = Float(sin(drift * 0.21) * 0.02)
        let yUpper = Float(stopLocations[1]) + bob
        let yLower = Float(stopLocations[2]) - bob
        let xMid: Float = 0.5 + sway

        // Outer frame pinned to the rectangle edges (full bleed, no gaps); only
        // the interior y-rows and the middle column drift.
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, yUpper), SIMD2<Float>(xMid, yUpper), SIMD2<Float>(1, yUpper),
            SIMD2<Float>(0, yLower), SIMD2<Float>(xMid, yLower), SIMD2<Float>(1, yLower),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
        ]

        return SkyMesh(width: 3, height: 4, points: points, colors: colors)
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

/// A resolved `MeshGradient` description — grid dimensions, unit-square control
/// points, and per-point colours — derived from the sky keyframes by
/// ``SundownPalette/skyMesh(light:proximity:drift:)``. Bundled so `SundownSky`
/// can hand it straight to a `MeshGradient` without re-deriving the layout.
struct SkyMesh {
    let width: Int
    let height: Int
    let points: [SIMD2<Float>]
    let colors: [Color]
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
