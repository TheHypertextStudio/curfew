import AppKit
@testable import Curfew
import CurfewAtmosphere
import Foundation
import SwiftUI
import Testing

/// Text over the sky stays readable on every sky from first light to curfew.
///
/// The view shades the sky behind each piece of text only as much as that sky
/// needs (`TodaySkyLegibility.shade`). These tests check the two halves of
/// that promise: across a 7 AM to 6 PM day, in five-minute steps and four band
/// phases, the opacity chosen, reduced to the coverage the blurred shade
/// actually reaches, gives the numerals 3:1 and every line and button 4.5:1;
/// and rendering the shade shows it reaches at least that coverage everywhere
/// behind the text.
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

    private func day() -> [HorizonFrame] {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return stride(from: 0.0, through: 660, by: 5).map { minute in
            HorizonMoment(
                now: start.addingTimeInterval(minute * 60), dayStart: start,
                curfew: start.addingTimeInterval(660 * 60),
                nextUnlock: start.addingTimeInterval(24 * 3600)
            ).frame
        }
    }

    /// The lowest contrast over `region` with the shade reduced to its
    /// measured coverage.
    private func lowest(
        in region: HorizonUnitRegion, frame: HorizonFrame, size: CGSize, opacity: Double
    ) -> Double {
        let canvas = HorizonField.Canvas(
            aspect: size.width / size.height, pixelHeight: size.height
        )
        let density = opacity * TodaySkyLegibility.coverage
        return TodaySkyLegibility.samples(in: region, frame: frame, canvas: canvas)
            .map {
                TodaySkyLegibility.contrast(
                    TodaySkyLegibility.ink,
                    TodaySkyLegibility.shaded($0, frame: frame, density: density)
                )
            }
            .min() ?? 0
    }

    @Test("The chosen shade gives numerals 3:1 and every line and button 4.5:1 all day")
    func todayTextIsLegible() {
        for surface in Self.surfaces {
            let regions = surface.metrics.textRegions(in: surface.size)
            for (index, frame) in day().enumerated() {
                let shade = TodaySkyLegibility.shade(
                    for: frame, size: surface.size, regions: regions
                )
                // The view draws one shade behind the whole block.
                let block = shade.block
                let numerals = lowest(
                    in: regions.numerals, frame: frame, size: surface.size, opacity: block
                )
                let line = lowest(
                    in: regions.line, frame: frame, size: surface.size, opacity: block
                )
                let actions = lowest(
                    in: regions.actions, frame: frame, size: surface.size,
                    opacity: block
                )
                let moment = "\(surface.name), minute \(index * 5)"
                #expect(numerals >= TodaySkyLegibility.largeTextRatio, "numerals \(moment)")
                #expect(line >= TodaySkyLegibility.textRatio, "line \(moment)")
                #expect(actions >= TodaySkyLegibility.textRatio, "actions \(moment)")
            }
        }
    }

    @Test("No shade is drawn where the sky already passes, and the bright day needs one")
    func shadeOnlyWhereNeeded() {
        let surface = Self.surfaces[0]
        let regions = surface.metrics.textRegions(in: surface.size)
        let shades = day().map {
            TodaySkyLegibility.shade(for: $0, size: surface.size, regions: regions)
        }
        #expect(shades.contains { $0.numerals == 0 })
        #expect(shades.contains { $0.numerals > 0 })
    }

    /// Renders the blurred shade in black over white, and reads how dark it is
    /// at every point of the text rectangle it sits behind.
    private func renderedCoverage(text size: CGSize, spread: CGFloat) throws -> Double {
        let margin = (spread * 3).rounded()
        let view = Color.clear
            .frame(width: size.width.rounded(), height: size.height.rounded())
            .background {
                TodaySkyShadeShape(color: .black, opacity: 1, spread: spread)
            }
            .padding(margin)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var least = 1.0
        let top = Int(margin)
        for row in top ..< min(height, top + Int(size.height.rounded())) {
            for column in top ..< min(width, top + Int(size.width.rounded())) {
                let red = Double(bytes[(row * width + column) * 4]) / 255
                least = min(least, 1 - red)
            }
        }
        return least
    }

    @Test("The blurred shade reaches its stated coverage behind every piece of text")
    func shadeCoverage() throws {
        for metrics in [TodayMetrics.window(CGSize(width: 832, height: 720)), .popover] {
            // One shade covers the block; the narrowest is short numerals over
            // a short line and one button.
            let block = try renderedCoverage(
                text: CGSize(
                    width: metrics.numeral * 1.8,
                    height: metrics.numeral * 1.25 + metrics.line * 1.5 + metrics.lineToActions
                        + (metrics.stacksActions ? 96 : 44)
                ),
                spread: metrics.shadeSpread
            )
            #expect(block >= TodaySkyLegibility.coverage, "\(block)")
        }
    }
}
