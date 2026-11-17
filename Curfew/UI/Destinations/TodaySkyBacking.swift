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

    /// Each region with the contrast its text needs.
    var needs: [(region: HorizonUnitRegion, ratio: Double)] {
        [
            (numerals, TodaySkyLegibility.largeTextRatio),
            (line, TodaySkyLegibility.textRatio),
            (actions, TodaySkyLegibility.textRatio)
        ]
    }

    /// The smallest rectangle holding all three.
    var block: HorizonUnitRegion {
        let all = [numerals, line, actions]
        return HorizonUnitRegion(
            minX: all.map(\.minX).min() ?? 0, maxX: all.map(\.maxX).max() ?? 1,
            minY: all.map(\.minY).min() ?? 0, maxY: all.map(\.maxY).max() ?? 1
        )
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
}

/// Keeps warm white text readable on every sky without drawing anything over it.
///
/// Nothing is laid on the sky. The sky itself is quieted behind the text
/// (``HorizonHush``): first the horizon's glow is taken out under the text
/// block, and only if that is not enough (the sun close to the countdown)
/// are all of the sky's levels lowered together, which keeps every band's
/// shape and the sun's rings round. Both act before the field is cut into
/// bands, so the result is still the sky's own hard-edged steps with no edge
/// or patch of another colour.
///
/// The measure is phase independent: a band's ramp position never exceeds
/// the brightness under it by more than the widest anti-aliased edge
/// (``margin``), so holding the brightness under each piece of text at or
/// below the brightest ramp position that still gives its contrast holds it
/// for every band phase. `TodaySkyLegibilityTests` checks the colours
/// actually drawn.
enum TodaySkyLegibility {
    /// Warm white, the ink over the sky.
    static let ink = HorizonRGB(0.99, 0.97, 0.94)
    /// Large numerals and headlines.
    static let largeTextRatio = 3.0
    /// Every other line, and button labels.
    static let textRatio = 4.5
    /// The furthest an anti-aliased band edge can lift the ramp position
    /// above the brightness under it: the shader's widest edge, in bands.
    static let margin = 0.45 / Double(HorizonGeometry.bandCount)
    /// How far the glow's dome reaches past the text block, as multiples of
    /// the block's half-width and half-height.
    static let reach = (across: 2.1, above: 2.25)

    /// The hush for Today's text on a sky of `size` at this moment.
    static func hush(
        for frame: HorizonFrame, size: CGSize, regions: TodayTextRegions,
        palette: HorizonPalette = .standard
    ) -> HorizonHush {
        guard size.width > 0, size.height > 0 else { return .none }
        let aspect = Double(size.width / size.height)
        let shape = dome(for: regions.block, aspect: aspect)
        let limits = regions.needs.map { need in
            Limit(
                points: grid(in: need.region),
                level: brightestPosition(for: frame, ratio: need.ratio, palette: palette) - margin
            )
        }
        func measure(glow: Double) -> Measure {
            var trial = shape
            trial.glow = glow
            return Measure(limits: limits, frame: frame, aspect: aspect, hush: trial)
        }
        if measure(glow: 0).scale >= 1 {
            return .none
        }
        var result = shape
        if measure(glow: 1).scale < 1 {
            result.glow = 1
        } else {
            var low = 0.0
            var high = 1.0
            for _ in 0 ..< 14 {
                let middle = (low + high) / 2
                if measure(glow: middle).scale >= 1 {
                    high = middle
                } else {
                    low = middle
                }
            }
            result.glow = high
        }
        let measured = measure(glow: result.glow)
        if measured.scale < 1 {
            result.scale = measured.scale
            result.knee = measured.brightest
        }
        return result
    }

    /// The glow's dome over the text block, with nothing taken out yet.
    private static func dome(for block: HorizonUnitRegion, aspect: Double) -> HorizonHush {
        HorizonHush(
            centre: HorizonPoint(
                x: (block.minX + block.maxX) / 2,
                y: (block.minY + block.maxY) / 2
            ),
            radiusX: (block.maxX - block.minX) / 2 * aspect * reach.across,
            radiusY: (block.maxY - block.minY) / 2 * reach.above,
            glow: 0, scale: 1, knee: 1
        )
    }

    /// Points under one piece of text and the brightest level they may reach.
    private struct Limit {
        var points: [HorizonPoint]
        var level: Double
    }

    /// The brightest level under the text for one hush, and the scale that
    /// brings every point down to its limit.
    private struct Measure {
        var brightest = 0.0
        var scale = 1.0

        init(limits: [Limit], frame: HorizonFrame, aspect: Double, hush: HorizonHush) {
            for limit in limits {
                for point in limit.points {
                    let level = HorizonField.brightness(
                        at: point, aspect: aspect, frame: frame, hush: hush
                    )
                    self.brightest = max(brightest, level)
                    if level > limit.level {
                        self.scale = min(scale, max(limit.level, 0) / level)
                    }
                }
            }
        }
    }

    /// The brightest ramp position whose colour still gives warm white
    /// `ratio` against it, at this moment's elevation.
    static func brightestPosition(
        for frame: HorizonFrame, ratio: Double, palette: HorizonPalette = .standard
    ) -> Double {
        func passes(_ position: Double) -> Bool {
            let color = palette.ramp(position, elevation: frame.elevation + (position - 0.5) * 0.24)
            return contrast(ink, color) >= ratio
        }
        guard passes(0) else { return 0 }
        var low = 0.0
        var high = 1.0
        if passes(high) {
            return high
        }
        for _ in 0 ..< 20 {
            let middle = (low + high) / 2
            if passes(middle) {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    /// A 25 by 13 grid of points over `region`.
    static func grid(in region: HorizonUnitRegion) -> [HorizonPoint] {
        var points: [HorizonPoint] = []
        points.reserveCapacity(25 * 13)
        for column in 0 ... 24 {
            for row in 0 ... 12 {
                points.append(HorizonPoint(
                    x: region.minX + (region.maxX - region.minX) * Double(column) / 24,
                    y: region.minY + (region.maxY - region.minY) * Double(row) / 12
                ))
            }
        }
        return points
    }

    /// Relative luminance of an sRGB colour.
    static func luminance(_ color: HorizonRGB) -> Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }

    /// WCAG contrast ratio between two sRGB colours.
    static func contrast(_ first: HorizonRGB, _ second: HorizonRGB) -> Double {
        let one = luminance(first)
        let two = luminance(second)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }
}

extension HorizonSkyView {
    /// The sky behind Today's text, quieted so `metrics`' text reads at
    /// every moment, in `palette`.
    init(
        today frame: HorizonFrame, isDayRunning: Bool, palette: HorizonPalette,
        metrics: @escaping (CGSize) -> TodayMetrics
    ) {
        self.init(frame: frame, isDayRunning: isDayRunning) { size in
            TodaySkyLegibility.hush(
                for: frame, size: size, regions: metrics(size).textRegions(in: size),
                palette: palette
            )
        }
    }
}
