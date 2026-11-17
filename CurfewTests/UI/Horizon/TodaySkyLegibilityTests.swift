@testable import Curfew
import CurfewAtmosphere
import Foundation
import Testing

/// Text over the sky stays readable on every sky from first light to curfew,
/// with no scrim. The test walks a 7 AM to 6 PM day in five-minute steps and
/// four band phases, samples the CPU reference field over the area each line
/// of text occupies, and checks warm white against the colour at a glyph's
/// edge, where the ground halo lies over the band (see `TodaySkyLegibility`).
/// Large numerals need 3:1; every other line needs 4.5:1.
@MainActor
struct TodaySkyLegibilityTests {
    /// A rectangle in the unit scene frame (y up).
    private struct Region {
        var minX: Double
        var maxX: Double
        var minY: Double
        var maxY: Double
    }

    private struct Surface {
        var name: String
        var size: CGSize
        var span: HorizonSpan
        /// Text centre as a fraction of the sky's width.
        var centerX: Double
        var metrics: TodayMetrics
        /// The actions' height, stacked or in one row.
        var actionsHeight: Double
    }

    private static let surfaces = [
        Surface(
            name: "detail beside the sidebar", size: CGSize(width: 832, height: 720),
            span: .fullBleed, centerX: 0.5,
            metrics: .window(CGSize(width: 832, height: 720)), actionsHeight: 44
        ),
        Surface(
            name: "smallest window", size: CGSize(width: 732, height: 660),
            span: .fullBleed, centerX: 0.5,
            metrics: .window(CGSize(width: 732, height: 660)), actionsHeight: 44
        ),
        Surface(
            name: "full bleed", size: CGSize(width: 1440, height: 900), span: .fullBleed,
            centerX: 0.5, metrics: .window(CGSize(width: 1440, height: 900)), actionsHeight: 44
        ),
        Surface(
            name: "menu bar popover", size: CGSize(width: 340, height: ContentView.skyHeight),
            span: .fullBleed, centerX: 0.5, metrics: .popover, actionsHeight: 96
        )
    ]

    /// The numerals' and the line's areas, from the layout's own metrics,
    /// each widened so a longer string or a rolled digit stays inside.
    private func regions(for surface: Surface) -> (numerals: Region, line: Region) {
        let height = surface.size.height
        let width = surface.size.width
        let metrics = surface.metrics
        let horizon = height * (1 - HorizonGeometry.horizon)
        let actionsTop = horizon - metrics.actionsToHorizon - surface.actionsHeight
        let lineBottom = actionsTop - metrics.lineToActions
        let lineTop = lineBottom - metrics.line * 1.5
        let numeralsBottom = lineTop - metrics.headlineToLine
        let numeralsTop = numeralsBottom - metrics.numeral * 1.25
        func unitY(_ top: Double) -> Double {
            1 - top / height
        }
        func across(_ points: Double) -> (Double, Double) {
            let half = points / 2 / width
            return (max(0, surface.centerX - half), min(1, surface.centerX + half))
        }
        let numeralsX = across(metrics.numeral * 2.8)
        let lineX = across(min(width - 32, 420))
        return (
            Region(
                minX: numeralsX.0, maxX: numeralsX.1,
                minY: unitY(numeralsBottom), maxY: unitY(numeralsTop)
            ),
            Region(minX: lineX.0, maxX: lineX.1, minY: unitY(lineBottom), maxY: unitY(lineTop))
        )
    }

    private func day(span: HorizonSpan) -> [HorizonFrame] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return stride(from: 0.0, through: 660, by: 5).map { minute in
            HorizonMoment(
                now: start.addingTimeInterval(minute * 60), dayStart: start,
                curfew: start.addingTimeInterval(660 * 60),
                nextUnlock: start.addingTimeInterval(24 * 3600), span: span
            ).frame
        }
    }

    /// The lowest contrast of warm white over `region` across the day.
    private func lowestContrast(
        in region: Region, surface: Surface, halo: Bool
    ) -> (ratio: Double, at: String) {
        let canvas = HorizonField.Canvas(
            aspect: surface.size.width / surface.size.height, pixelHeight: surface.size.height
        )
        var lowest = (ratio: Double.infinity, at: "")
        for (index, frame) in day(span: surface.span).enumerated() {
            for phase in [0.0, 0.25, 0.5, 0.75] {
                for column in 0 ... 12 {
                    for row in 0 ... 6 {
                        let point = HorizonPoint(
                            x: region.minX + (region.maxX - region.minX) * Double(column) / 12,
                            y: region.minY + (region.maxY - region.minY) * Double(row) / 6
                        )
                        let sky = HorizonField.color(
                            at: point, canvas: canvas, frame: frame,
                            bands: HorizonField.Bands(phase: phase, edgeWidth: 0)
                        )
                        let edge = halo ? TodaySkyLegibility.edge(over: sky, frame: frame) : sky
                        let ratio = TodaySkyLegibility.contrast(TodaySkyLegibility.ink, edge)
                        if ratio < lowest.ratio {
                            lowest = (ratio, "minute \(index * 5) at \(point)")
                        }
                    }
                }
            }
        }
        return lowest
    }

    @Test("Countdown numerals keep 3:1 and the line under them 4.5:1 on every sky")
    func todayTextIsLegible() {
        for surface in Self.surfaces {
            let area = regions(for: surface)
            let numerals = lowestContrast(in: area.numerals, surface: surface, halo: true)
            let line = lowestContrast(in: area.line, surface: surface, halo: true)
            #expect(numerals.ratio >= 3, "\(surface.name) numerals \(numerals)")
            #expect(line.ratio >= 4.5, "\(surface.name) line \(line)")
        }
    }

    @Test("Without the halo the day sky alone is too bright, so the halo is load-bearing")
    func haloIsNeeded() {
        let surface = Self.surfaces[1]
        let numerals = lowestContrast(
            in: regions(for: surface).numerals,
            surface: surface,
            halo: false
        )
        #expect(numerals.ratio < 3)
    }
}
