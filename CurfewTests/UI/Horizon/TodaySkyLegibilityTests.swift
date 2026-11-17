@testable import Curfew
import CurfewAtmosphere
import Foundation
import Testing

/// Text over the sky stays readable on every sky from first light to curfew.
///
/// Nothing is drawn behind Today's text; the sky under it is quieted
/// (`TodaySkyLegibility.hush`). These tests check the colours the sky actually
/// takes under the text: across a 7 AM to 6 PM day, in five-minute steps and
/// four band phases, in every palette and on every Today surface, the numerals
/// get 3:1 and every line and button 4.5:1; and the CPU reference image, band
/// edges and all, keeps those ratios at the moments the snapshots show.
@MainActor
struct TodaySkyLegibilityTests {
    private struct Surface {
        var name: String
        var size: CGSize
        var metrics: TodayMetrics
    }

    private static let surfaces = [
        Surface(
            name: "detail beside the sidebar", size: CGSize(width: 832, height: 720),
            metrics: .window(CGSize(width: 832, height: 720))
        ),
        Surface(
            name: "smallest window", size: CGSize(width: 732, height: 660),
            metrics: .window(CGSize(width: 732, height: 660))
        ),
        Surface(
            name: "full bleed", size: CGSize(width: 1440, height: 900),
            metrics: .window(CGSize(width: 1440, height: 900))
        ),
        Surface(
            name: "menu bar popover",
            size: CGSize(width: ContentView.width, height: ContentView.skyHeight),
            metrics: .popover
        )
    ]

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func frame(minute: Double) -> HorizonFrame {
        HorizonMoment(
            now: start.addingTimeInterval(minute * 60), dayStart: start,
            curfew: start.addingTimeInterval(660 * 60),
            nextUnlock: start.addingTimeInterval(24 * 3600)
        ).frame
    }

    private func day() -> [HorizonFrame] {
        stride(from: 0.0, through: 660, by: 5).map { Self.frame(minute: $0) }
    }

    /// The lowest contrast of warm white over the sky drawn in `region`: a
    /// 13 by 7 grid at four band phases.
    private func lowest(
        in region: HorizonUnitRegion, frame: HorizonFrame, size: CGSize, hush: HorizonHush,
        palette: HorizonPalette
    ) -> Double {
        let canvas = HorizonField.Canvas(
            aspect: size.width / size.height, pixelHeight: size.height
        )
        var least = Double.infinity
        for phase in [0.0, 0.25, 0.5, 0.75] {
            for column in 0 ... 12 {
                for row in 0 ... 6 {
                    let point = HorizonPoint(
                        x: region.minX + (region.maxX - region.minX) * Double(column) / 12,
                        y: region.minY + (region.maxY - region.minY) * Double(row) / 6
                    )
                    if Self.isOnSunDisc(point, frame: frame, size: size) {
                        continue
                    }
                    let sky = HorizonField.color(
                        at: point, canvas: canvas, frame: frame,
                        bands: HorizonField.Bands(phase: phase, edgeWidth: 0),
                        palette: palette, hush: hush
                    )
                    least = min(least, TodaySkyLegibility.contrast(TodaySkyLegibility.ink, sky))
                }
            }
        }
        return least
    }

    /// True on the sun's disc (with its anti-aliased rim). The disc is not
    /// sky: the hush leaves it clean on purpose, and the old measure passed
    /// only by greying it. The regions are line boxes wider than the glyphs
    /// (and assume two stacked buttons in the popover), so on the popover's
    /// small sky the disc enters them while staying clear of the text itself;
    /// the popover renders through the day show it.
    private static func isOnSunDisc(
        _ point: HorizonPoint, frame: HorizonFrame, size: CGSize
    ) -> Bool {
        guard frame.sunWeight >= 0.01 else { return false }
        let aspect = size.width / size.height
        let distance = hypot((point.x - frame.sun.x) * aspect, point.y - frame.sun.y)
        return distance <= HorizonGeometry.sunRadius + 2 / size.height
    }

    @Test(
        "In every palette the quieted sky gives numerals 3:1 and every line and button 4.5:1",
        arguments: HorizonPalette.all
    )
    func todayTextIsLegible(palette: HorizonPalette) {
        for surface in Self.surfaces {
            let regions = surface.metrics.textRegions(in: surface.size)
            for (index, frame) in day().enumerated() {
                let hush = TodaySkyLegibility.hush(
                    for: frame, size: surface.size, regions: regions, palette: palette
                )
                func lowest(_ region: HorizonUnitRegion) -> Double {
                    self.lowest(
                        in: region, frame: frame, size: surface.size, hush: hush, palette: palette
                    )
                }
                let moment = "\(surface.name), minute \(index * 5)"
                #expect(
                    lowest(regions.numerals) >= TodaySkyLegibility.largeTextRatio,
                    "numerals \(moment)"
                )
                #expect(lowest(regions.line) >= TodaySkyLegibility.textRatio, "line \(moment)")
                #expect(
                    lowest(regions.actions) >= TodaySkyLegibility.textRatio, "actions \(moment)"
                )
            }
        }
    }

    @Test("The sky is left alone where it already passes, and the bright day is quieted")
    func hushOnlyWhereNeeded() {
        let surface = Self.surfaces[0]
        let regions = surface.metrics.textRegions(in: surface.size)
        // An hour after curfew the sky is dark enough on its own.
        let night = TodaySkyLegibility.hush(
            for: Self.frame(minute: 720), size: surface.size, regions: regions
        )
        #expect(night.isNone)
        let noon = TodaySkyLegibility.hush(
            for: Self.frame(minute: 330), size: surface.size, regions: regions
        )
        #expect(!noon.isNone)
    }

    @Test("The sun's own falloff is never quieted, so its rings stay round")
    func sunKeepsItsRings() {
        let surface = Self.surfaces[0]
        let regions = surface.metrics.textRegions(in: surface.size)
        let aspect = surface.size.width / surface.size.height
        // Mid-morning, when the sun passes closest to the countdown.
        let frame = Self.frame(minute: 150)
        let hush = TodaySkyLegibility.hush(
            for: frame, size: surface.size, regions: regions
        )
        #expect(!hush.isNone)
        // Around rings about the sun, the quieted sky is the model's sky put
        // through one monotonic remap, give or take well under half a band
        // from the glow taken out beneath the text, so each ring stays a ring.
        let halfBand = 0.5 / Double(HorizonGeometry.bandCount)
        for radius in [0.07, 0.09, 0.12] {
            for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 12) {
                let point = HorizonPoint(
                    x: frame.sun.x + cos(angle) * radius / aspect,
                    y: frame.sun.y + sin(angle) * radius
                )
                let model = HorizonField.brightness(at: point, aspect: aspect, frame: frame)
                let quieted = HorizonField.brightness(
                    at: point, aspect: aspect, frame: frame, hush: hush
                )
                #expect(abs(quieted - hush.toned(model)) < halfBand, "radius \(radius)")
            }
        }
    }

    /// The rendered sky behind each region, read pixel by pixel.
    @Test(
        "The CPU sky, band edges included, keeps the ratios at the snapshot moments",
        arguments: HorizonPalette.all
    )
    func renderedSkyIsLegible(palette: HorizonPalette) throws {
        let size = CGSize(width: 832, height: 720)
        let regions = TodayMetrics.window(size).textRegions(in: size)
        for minute in [150.0, 330, 510, 648, 658] {
            let frame = Self.frame(minute: minute)
            let hush = TodaySkyLegibility.hush(
                for: frame, size: size, regions: regions, palette: palette
            )
            let pixels = try #require(HorizonRenderer.pixels(
                frame: frame, bandPhase: 0.37, pixelWidth: Int(size.width),
                pixelHeight: Int(size.height), palette: palette, hush: hush
            ))
            for need in regions.needs {
                var least = Double.infinity
                let region = need.region
                let rows = Int((1 - region.maxY) * size.height) ...
                    Int((1 - region.minY) * size.height) - 1
                let columns = Int(region.minX * size.width) ... Int(region.maxX * size.width) - 1
                for row in rows {
                    for column in columns {
                        let offset = (row * Int(size.width) + column) * 4
                        let color = HorizonRGB(
                            Double(pixels[offset]) / 255, Double(pixels[offset + 1]) / 255,
                            Double(pixels[offset + 2]) / 255
                        )
                        least = min(
                            least, TodaySkyLegibility.contrast(TodaySkyLegibility.ink, color)
                        )
                    }
                }
                #expect(least >= need.ratio, "minute \(minute): \(least) < \(need.ratio)")
            }
        }
    }
}
