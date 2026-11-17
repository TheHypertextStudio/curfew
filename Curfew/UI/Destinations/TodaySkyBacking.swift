import CurfewAtmosphere
import SwiftUI

/// A rectangle in the Horizon scene's unit frame, y up.
struct HorizonUnitRegion: Equatable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
}

/// Where Today's text sits over the sky, in the scene's unit frame: the
/// numerals (or a statement), the line under them and the actions.
struct TodayTextRegions: Equatable {
    var numerals: HorizonUnitRegion
    var line: HorizonUnitRegion
    var actions: HorizonUnitRegion
}

/// How strongly the sky is shaded behind each piece of Today's text, from 0
/// (not at all) to 1. Zero wherever the sky behind already passes.
struct TodaySkyShade: Equatable {
    var numerals: Double
    var line: Double
    var actions: Double

    static let none = TodaySkyShade(numerals: 0, line: 0, actions: 0)

    /// The one shade drawn behind the whole block: enough for its neediest part.
    var block: Double {
        max(numerals, line, actions)
    }
}

extension TodayMetrics {
    /// The areas the sky block occupies on a sky of `size`, from the same
    /// arithmetic as the layout, each widened so a longer string or a rolled
    /// digit stays inside.
    func textRegions(in size: CGSize) -> TodayTextRegions {
        let height = Double(size.height)
        let width = Double(size.width)
        let horizon = height * (1 - HorizonGeometry.horizon)
        let actionsHeight = stacksActions ? 96.0 : 44.0
        let actionsBottom = horizon - Double(actionsToHorizon)
        let actionsTop = actionsBottom - actionsHeight
        let lineBottom = actionsTop - Double(lineToActions)
        let lineTop = lineBottom - Double(line) * 1.5
        let numeralsBottom = lineTop - Double(headlineToLine)
        let numeralsTop = numeralsBottom - Double(numeral) * 1.25
        func unitY(_ top: Double) -> Double {
            1 - top / height
        }
        func across(_ points: Double) -> (Double, Double) {
            let half = points / 2 / width
            return (max(0, 0.5 - half), min(1, 0.5 + half))
        }
        func region(width points: Double, top: Double, bottom: Double) -> HorizonUnitRegion {
            let span = across(points)
            return HorizonUnitRegion(
                minX: span.0, maxX: span.1, minY: unitY(bottom), maxY: unitY(top)
            )
        }
        return TodayTextRegions(
            numerals: region(
                width: Double(numeral) * 2.8,
                top: numeralsTop,
                bottom: numeralsBottom
            ),
            line: region(width: min(width - 32, 420), top: lineTop, bottom: lineBottom),
            actions: region(width: min(width - 32, 360), top: actionsTop, bottom: actionsBottom)
        )
    }

    /// How far the soft shade reaches past the block, and how soft it is.
    var shadeSpread: CGFloat {
        (numeral * 0.3).rounded()
    }
}

/// Keeps warm white text readable on every sky without a visible effect.
///
/// Each frame, the CPU field is sampled under the numerals, the line and the
/// actions. Where the sky already gives the text its contrast nothing is
/// drawn. Where it does not, a wide, soft shade of the moment's ground colour
/// sits behind that text at just the opacity needed: the sky reads a little
/// dimmer there, with no edge. `TodaySkyLegibilityTests` measures how much of
/// the shade reaches the text (``coverage``) and proves the contrast across
/// the day.
enum TodaySkyLegibility {
    /// Warm white, the ink over the sky.
    static let ink = HorizonRGB(0.99, 0.97, 0.94)
    /// Large numerals and headlines.
    static let largeTextRatio = 3.0
    /// Every other line, and button labels.
    static let textRatio = 4.5
    /// The least share of the shade's opacity that reaches any point of the
    /// text it sits behind, once blurred. Measured by the tests.
    static let coverage = 0.8
    private static let phases = [0.0, 0.25, 0.5, 0.75]

    /// The shade for each piece of text on a sky of `size`.
    static func shade(
        for frame: HorizonFrame, size: CGSize, regions: TodayTextRegions
    ) -> TodaySkyShade {
        guard size.width > 0, size.height > 0 else { return .none }
        let canvas = HorizonField.Canvas(
            aspect: Double(size.width / size.height), pixelHeight: Double(size.height)
        )
        func opacity(_ region: HorizonUnitRegion, ratio: Double) -> Double {
            let needed = requiredDensity(in: region, frame: frame, canvas: canvas, ratio: ratio)
            guard needed > 0 else { return 0 }
            // In steps of 0.05, so the shade changes rarely as the sun moves.
            return min(1, (needed / coverage * 20).rounded(.up) / 20)
        }
        return TodaySkyShade(
            numerals: opacity(regions.numerals, ratio: largeTextRatio),
            line: opacity(regions.line, ratio: textRatio),
            actions: opacity(regions.actions, ratio: textRatio)
        )
    }

    /// The least density of the ground colour over the sky that gives every
    /// sampled point of `region` the `ratio`, across the band phases.
    static func requiredDensity(
        in region: HorizonUnitRegion, frame: HorizonFrame, canvas: HorizonField.Canvas,
        ratio: Double
    ) -> Double {
        var needed = 0.0
        for sky in samples(in: region, frame: frame, canvas: canvas)
            where contrast(ink, shaded(sky, frame: frame, density: needed)) < ratio {
            var low = needed
            var high = 1.0
            for _ in 0 ..< 8 {
                let middle = (low + high) / 2
                if contrast(ink, shaded(sky, frame: frame, density: middle)) >= ratio {
                    high = middle
                } else {
                    low = middle
                }
            }
            needed = high
        }
        return needed
    }

    /// Sky colours under `region`: a 13 by 7 grid at four band phases.
    static func samples(
        in region: HorizonUnitRegion, frame: HorizonFrame, canvas: HorizonField.Canvas
    ) -> [HorizonRGB] {
        var colors: [HorizonRGB] = []
        colors.reserveCapacity(13 * 7 * phases.count)
        for phase in phases {
            for column in 0 ... 12 {
                for row in 0 ... 6 {
                    let point = HorizonPoint(
                        x: region.minX + (region.maxX - region.minX) * Double(column) / 12,
                        y: region.minY + (region.maxY - region.minY) * Double(row) / 6
                    )
                    colors.append(HorizonField.color(
                        at: point, canvas: canvas, frame: frame,
                        bands: HorizonField.Bands(phase: phase, edgeWidth: 0)
                    ))
                }
            }
        }
        return colors
    }

    /// The shade colour: the far sky as it looks just after curfew, so behind
    /// the text the sky reads as a deeper blue of its own palette rather than
    /// a grey overlay.
    static func ground(for frame: HorizonFrame) -> HorizonRGB {
        HorizonPalette.ramp(0, elevation: min(frame.elevation, 0) - 0.1)
    }

    /// `sky` under the shade at `density`.
    static func shaded(_ sky: HorizonRGB, frame: HorizonFrame, density: Double) -> HorizonRGB {
        let shade = ground(for: frame)
        return HorizonRGB(
            sky.red + (shade.red - sky.red) * density,
            sky.green + (shade.green - sky.green) * density,
            sky.blue + (shade.blue - sky.blue) * density
        )
    }

    /// WCAG contrast ratio between two sRGB colours.
    static func contrast(_ first: HorizonRGB, _ second: HorizonRGB) -> Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        func luminance(_ color: HorizonRGB) -> Double {
            0.2126 * channel(color.red) + 0.7152 * channel(color.green)
                + 0.0722 * channel(color.blue)
        }
        let one = luminance(first)
        let two = luminance(second)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }
}

/// The soft shade itself: a rounded rectangle reaching past the text, blurred
/// wide enough that it has no edge.
struct TodaySkyShadeShape: View {
    var color: Color
    var opacity: Double
    var spread: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: spread * 2.5, style: .continuous)
            .fill(color.opacity(opacity))
            .padding(-spread * 1.75)
            .blur(radius: spread * 0.9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A soft shade of the moment's ground colour behind this text, at
    /// `opacity`; nothing when the sky already passes.
    func skyShade(_ opacity: Double, frame: HorizonFrame, spread: CGFloat) -> some View {
        background {
            if opacity > 0 {
                let ground = TodaySkyLegibility.ground(for: frame)
                TodaySkyShadeShape(
                    color: AtmospherePalette.solidBackground(
                        red: ground.red, green: ground.green, blue: ground.blue
                    ),
                    opacity: opacity,
                    spread: spread
                )
                .animation(.easeInOut(duration: 1), value: opacity)
            }
        }
    }
}
