import CoreGraphics
@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

/// A theme's sky is a complete palette drawn by the one field. Every palette
/// must feed the shader the same table the CPU renderer reads, keep the
/// stepped hand (light rises toward the sun, night is darker than day), and
/// keep warm white text legible on the lock.
struct HorizonPaletteTests {
    private static let ink = HorizonRGB(0.99, 0.97, 0.94)

    private static func luminance(_ color: HorizonRGB) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = min(max(channel, 0), 1)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private static func contrast(_ lhs: HorizonRGB, _ rhs: HorizonRGB) -> Double {
        let (high, low) = (max(luminance(lhs), luminance(rhs)), min(luminance(lhs), luminance(rhs)))
        return (high + 0.05) / (low + 0.05)
    }

    @Test("Saved choices map onto the authored palettes, so old preferences keep their mood")
    func savedChoicesMap() {
        #expect(HorizonPalette(.sundown) == .standard)
        #expect(HorizonPalette(.warmAmber) == .desert)
        #expect(HorizonPalette(.coolTwilight) == .polar)
        #expect(HorizonPalette.all == [.standard, .desert, .polar])
    }

    @Test("Every palette is distinct from the others at every moment")
    func palettesAreDistinct() {
        for (index, palette) in HorizonPalette.all.enumerated() {
            for other in HorizonPalette.all[(index + 1)...] {
                #expect(palette.day != other.day)
                #expect(palette.lastHour != other.lastHour)
                #expect(palette.dusk != other.dusk)
                #expect(palette.night != other.night)
                #expect(palette.nightGround != other.nightGround)
            }
        }
    }

    @Test("Each palette's shader table is its own ramps, grounds and moon, in shader order")
    func shaderTableMatchesPalette() {
        for palette in HorizonPalette.all {
            let table = palette.shaderTable
            #expect(table.count == HorizonPalette.shaderTableCount)
            func entry(_ stop: Int, _ moment: Int) -> [Float] {
                let index = (stop * 4 + moment) * 3
                return Array(table[index ..< index + 3])
            }
            func floats(_ color: HorizonRGB) -> [Float] {
                [Float(color.red), Float(color.green), Float(color.blue)]
            }
            for stop in 0 ..< 5 {
                #expect(entry(stop, 0) == floats(palette.day[stop]))
                #expect(entry(stop, 1) == floats(palette.lastHour[stop]))
                #expect(entry(stop, 2) == floats(palette.dusk[stop]))
                #expect(entry(stop, 3) == floats(palette.night[stop]))
            }
            #expect(entry(5, 0) == floats(palette.dayGround))
            #expect(entry(5, 3) == floats(palette.nightGround))
            #expect(Array(table[72 ..< 75]) == floats(palette.moonLit))
            #expect(Array(table[75 ..< 78]) == floats(palette.moonDark))
        }
    }

    @Test("The shader source reads the moon from the table and requires the full table")
    func shaderReadsWholeTable() throws {
        let shader = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CurfewAtmosphereTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // CurfewKit/
            .deletingLastPathComponent() // <repo>/
            .appendingPathComponent("Curfew/UI/Horizon/HorizonSky.metal")
        let source = try String(contentsOf: shader, encoding: .utf8)
        #expect(source.contains("TABLE_COUNT = \(HorizonPalette.shaderTableCount);"))
        #expect(source.contains("MOON = 72;"))
        // No palette colour is baked into the shader.
        #expect(!source.contains("float3(0.93, 0.92, 0.97)"))
        #expect(!source.contains("float3(0.2, 0.22, 0.42)"))
    }

    @Test("The renderer draws the palette it is given, ground and moon included")
    func rendererUsesPalette() throws {
        let frame = HorizonFrame(
            sun: HorizonPoint(x: 0.5, y: -1), sunWeight: 0,
            moon: HorizonPoint(x: 0.5, y: 0.7), moonWeight: 1,
            elevation: -0.9, moonPhase: .pi
        )
        for palette in HorizonPalette.all {
            let pixels = try #require(HorizonRenderer.pixels(
                frame: frame, bandPhase: 0, pixelWidth: 160, pixelHeight: 100, palette: palette
            ))
            let ground = (99 * 160 + 80) * 4
            #expect(Array(pixels[ground ..< ground + 3]) == palette.ground(elevation: -0.9).bytes)
            // The moon's centre, full: its lit face, with no sky mixed in.
            // Compared as a colour, since GLSL's mix(sky, lit, 1) can land one
            // ulp either side of the lit value: Polar's lit red, 0.90, is
            // exactly 229.5 of 255, so its byte may round either way.
            let moon = (30 * 160 + 80) * 4
            let centre = HorizonPoint(x: 80.5 / 160, y: 1 - 30.5 / 100)
            let colour = palette.fieldColor(
                at: centre,
                level: HorizonField.brightness(at: centre, aspect: 1.6, frame: frame),
                canvas: HorizonField.Canvas(aspect: 1.6, pixelHeight: 100), frame: frame,
                bands: HorizonField.Bands(phase: 0, edgeWidth: 0)
            )
            #expect(abs(colour.red - palette.moonLit.red) < 1e-12)
            #expect(abs(colour.green - palette.moonLit.green) < 1e-12)
            #expect(abs(colour.blue - palette.moonLit.blue) < 1e-12)
            for (drawn, lit) in zip(pixels[moon ..< moon + 3], palette.moonLit.bytes) {
                #expect(abs(Int(drawn) - Int(lit)) <= 1)
            }
        }
    }

    @Test("Within each ramp, light rises from far sky to nearest the light")
    func rampsBrightenTowardTheLight() {
        for palette in HorizonPalette.all {
            for ramp in [palette.day, palette.lastHour, palette.dusk, palette.night] {
                let levels = ramp.map(Self.luminance)
                #expect(levels == levels.sorted(), "\(ramp) does not rise toward the light")
            }
        }
    }

    @Test("Night is darker than dusk, dusk than the last hour, the last hour than day")
    func momentsDarkenTowardNight() {
        for palette in HorizonPalette.all {
            func mean(_ ramp: [HorizonRGB]) -> Double {
                ramp.map(Self.luminance).reduce(0, +) / Double(ramp.count)
            }
            #expect(mean(palette.night) < mean(palette.dusk))
            #expect(mean(palette.dusk) < mean(palette.lastHour))
            #expect(mean(palette.lastHour) < mean(palette.day))
            #expect(Self.luminance(palette.nightGround) < Self.luminance(palette.dayGround))
        }
    }

    @Test("Warm white text reads on every lock and every ground")
    func lockTextIsLegible() {
        for palette in HorizonPalette.all {
            // The lock is the night sky; its brightest band sits by the moon.
            for stop in palette.night {
                #expect(Self.contrast(Self.ink, stop) >= 4.5, "\(stop) is too light for text")
            }
            // The one thing and Sunrise's answer sit on the ground.
            for ground in [
                palette.dayGround, palette.lastHourGround, palette.duskGround, palette.nightGround
            ] {
                #expect(Self.contrast(Self.ink, ground) >= 7, "\(ground) is too light for text")
            }
        }
    }
}
