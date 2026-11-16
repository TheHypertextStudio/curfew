import CoreGraphics
@testable import CurfewAtmosphere
import Foundation
import Testing

/// The field, the 14-step quantisation and the ramps match the prototype shader,
/// so the CPU reference renderer and the Metal shader agree pixel for pixel.
struct HorizonFieldTests {
    private func expectColor(
        _ actual: HorizonRGB, _ expected: (Double, Double, Double),
        tolerance: Double = 1e-9, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual.red - expected.0) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(actual.green - expected.1) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(actual.blue - expected.2) < tolerance, sourceLocation: sourceLocation)
    }

    private let canvas = HorizonField.Canvas(aspect: 1.6, pixelHeight: 900)
    private let sharp = HorizonField.Bands(phase: 0, edgeWidth: 0)

    private func near(_ lhs: HorizonRGB, _ rhs: HorizonRGB) -> Bool {
        abs(lhs.red - rhs.red) < 1e-9 && abs(lhs.green - rhs.green) < 1e-9
            && abs(lhs.blue - rhs.blue) < 1e-9
    }

    private static let day: [(Double, Double, Double)] = [
        (0.10, 0.27, 0.66), (0.22, 0.44, 0.82), (0.44, 0.64, 0.91),
        (0.70, 0.82, 0.95), (0.94, 0.96, 0.98)
    ]
    private static let dusk: [(Double, Double, Double)] = [
        (0.07, 0.08, 0.24), (0.20, 0.15, 0.42), (0.50, 0.22, 0.45),
        (0.83, 0.34, 0.30), (0.96, 0.62, 0.30)
    ]
    private static let night: [(Double, Double, Double)] = [
        (0.027, 0.031, 0.094), (0.047, 0.059, 0.165), (0.10, 0.12, 0.31),
        (0.135, 0.155, 0.37), (0.19, 0.21, 0.46)
    ]

    @Test("High sun uses the day ramp stop for stop")
    func dayRamp() {
        for (index, stop) in Self.day.enumerated() {
            expectColor(HorizonPalette.ramp(Double(index) / 4, elevation: 0.6), stop)
        }
        expectColor(HorizonPalette.ground(elevation: 0.6), (0.07, 0.11, 0.29))
    }

    @Test("At elevation 0.1 the ramp is the last-hour palette")
    func lastHourRamp() {
        for (index, stop) in HorizonPalette.lastHour.enumerated() {
            expectColor(
                HorizonPalette.ramp(Double(index) / 4, elevation: 0.1),
                (stop.red, stop.green, stop.blue)
            )
        }
        expectColor(HorizonPalette.lastHour[0], (0.15, 0.17, 0.46))
        expectColor(HorizonPalette.lastHour[1], (0.38, 0.27, 0.60))
        expectColor(HorizonPalette.lastHour[4], (1.0, 0.84, 0.52))
        expectColor(HorizonPalette.ground(elevation: 0.1), (0.11, 0.085, 0.25))
    }

    @Test("Just below the horizon the ramp is dusk, and deep night is night")
    func duskAndNightRamps() {
        for (index, stop) in Self.dusk.enumerated() {
            expectColor(HorizonPalette.ramp(Double(index) / 4, elevation: -0.05), stop)
        }
        for (index, stop) in Self.night.enumerated() {
            expectColor(HorizonPalette.ramp(Double(index) / 4, elevation: -0.4), stop)
            expectColor(HorizonPalette.ramp(Double(index) / 4, elevation: -0.9), stop)
        }
        expectColor(HorizonPalette.ground(elevation: -0.05), (0.065, 0.05, 0.18))
        expectColor(HorizonPalette.ground(elevation: -0.9), (0.018, 0.02, 0.055))
    }

    @Test("The shader table lays out six stops of four palettes")
    func shaderTable() {
        let table = HorizonPalette.shaderTable
        #expect(table.count == 72)
        // Stop 0, day.
        #expect(Array(table[0 ..< 3]) == [0.10, 0.27, 0.66])
        // Stop 2, night.
        #expect(Array(table[33 ..< 36]) == [0.10, 0.12, 0.31])
        // Ground, last hour.
        #expect(Array(table[63 ..< 66]) == [0.11, 0.085, 0.25])
    }

    @Test("Between stops the ramp interpolates linearly")
    func rampInterpolates() {
        let between = HorizonPalette.ramp(0.125, elevation: 0.6)
        expectColor(between, (0.16, 0.355, 0.74))
    }

    @Test("Brightness is quantised into exactly 14 steps")
    func fourteenSteps() {
        var steps = Set<Double>()
        for index in 0 ..< 10000 {
            let level = Double(index) / 10000
            steps.insert(HorizonField.quantised(level, bandPhase: 0, edgeWidth: 0))
        }
        #expect(steps.count == HorizonGeometry.bandCount)
        #expect(HorizonGeometry.bandCount == 14)
    }

    @Test("Band phase slides the band edges without changing the step size")
    func bandPhaseShiftsEdges() {
        let still = HorizonField.quantised(0.5 + 0.2 / 14, bandPhase: 0, edgeWidth: 0)
        let shifted = HorizonField.quantised(0.5 + 0.2 / 14, bandPhase: 0.9, edgeWidth: 0)
        #expect(still != shifted)
        let nextBand = HorizonField.quantised(0.5 + 1.2 / 14, bandPhase: 0.9, edgeWidth: 0)
        #expect(abs(nextBand - shifted - 1.0 / 14) < 1e-9)
        // A whole band of phase is indistinguishable from none.
        #expect(abs(
            HorizonField.quantised(0.37, bandPhase: 1.3, edgeWidth: 0)
                - HorizonField.quantised(0.37, bandPhase: 0.3, edgeWidth: 0)
        ) < 1e-9)
    }

    @Test("Brightness is the screen blend of the sun, moon and horizon falloffs")
    func brightnessBlend() {
        let frame = HorizonFrame(
            sun: HorizonPoint(x: 0.5, y: 0.6), sunWeight: 1,
            moon: HorizonPoint(x: 0.2, y: 0.8), moonWeight: 0,
            elevation: 1, moonPhase: 0
        )
        let atSun = HorizonField.brightness(
            at: HorizonPoint(x: 0.5, y: 0.6), aspect: 1.6, frame: frame
        )
        // At the sun's centre its falloff is 1, so the screen blend is full.
        #expect(abs(atSun - 1) < 1e-9)
        let away = HorizonField.brightness(
            at: HorizonPoint(x: 0.1, y: 0.9), aspect: 1.6, frame: frame
        )
        #expect(away < atSun)
        #expect(away > 0)
    }

    @Test("Below the horizon is one flat ground colour")
    func groundIsFlat() {
        let frame = HorizonMoment(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            dayStart: Date(timeIntervalSince1970: 1_800_000_000 - 4 * 3600),
            curfew: Date(timeIntervalSince1970: 1_800_000_000 + 4 * 3600),
            nextUnlock: Date(timeIntervalSince1970: 1_800_000_000 + 16 * 3600)
        ).frame
        let ground = HorizonPalette.ground(elevation: frame.elevation)
        for across in stride(from: 0.0, through: 1.0, by: 0.1) {
            for height in stride(from: 0.0, to: HorizonGeometry.horizon, by: 0.05) {
                let color = HorizonField.color(
                    at: HorizonPoint(x: across, y: height), canvas: canvas, frame: frame,
                    bands: HorizonField.Bands(phase: 0.3, edgeWidth: 0)
                )
                #expect(color == ground)
            }
        }
    }

    @Test("The sun disc is drawn in the brightest stop with a 0.05 radius")
    func sunDisc() {
        let frame = HorizonFrame(
            sun: HorizonPoint(x: 0.5, y: 0.6), sunWeight: 1,
            moon: HorizonPoint(x: 0.2, y: 0.8), moonWeight: 0,
            elevation: 0.3, moonPhase: 0
        )
        let disc = HorizonPalette.ramp(1, elevation: 0.42).scaled(1.02).offset(0.03)
        let centre = HorizonField.color(
            at: HorizonPoint(x: 0.5, y: 0.6), canvas: canvas, frame: frame, bands: sharp
        )
        #expect(near(centre, disc))
        let outside = HorizonField.color(
            at: HorizonPoint(x: 0.5, y: 0.6 + HorizonGeometry.sunRadius * 1.2),
            canvas: canvas, frame: frame, bands: sharp
        )
        #expect(!near(outside, disc))
    }

    @Test("The moon's lit side follows the phase angle")
    func moonTerminator() {
        func moonColor(phase: Double, offset: Double) -> HorizonRGB {
            let frame = HorizonFrame(
                sun: HorizonPoint(x: 0.5, y: -1), sunWeight: 0,
                moon: HorizonPoint(x: 0.5, y: 0.7), moonWeight: 1,
                elevation: -0.9, moonPhase: phase
            )
            return HorizonField.color(
                at: HorizonPoint(x: 0.5 + offset * HorizonGeometry.moonRadius / 1.6, y: 0.7),
                canvas: canvas, frame: frame, bands: sharp
            )
        }
        let lit = HorizonRGB(0.93, 0.92, 0.97)
        let dark = HorizonRGB(0.2, 0.22, 0.42)
        // Full moon: lit everywhere on the disc.
        #expect(near(moonColor(phase: .pi, offset: 0.5), lit))
        #expect(near(moonColor(phase: .pi, offset: -0.5), lit))
        // New moon: dark everywhere on the disc.
        #expect(near(moonColor(phase: 0.0001, offset: 0.5), dark))
        // First quarter: the right half is lit.
        #expect(near(moonColor(phase: .pi / 2, offset: 0.5), lit))
        #expect(near(moonColor(phase: .pi / 2, offset: -0.5), dark))
    }

    @Test("The reference renderer produces an image of the requested pixel size")
    func rendererSize() throws {
        let frame = HorizonMoment(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            dayStart: Date(timeIntervalSince1970: 1_800_000_000 - 4 * 3600),
            curfew: Date(timeIntervalSince1970: 1_800_000_000 + 4 * 3600),
            nextUnlock: Date(timeIntervalSince1970: 1_800_000_000 + 16 * 3600)
        ).frame
        let image = try #require(HorizonRenderer.image(
            frame: frame, bandPhase: 0.3, pixelWidth: 160, pixelHeight: 100
        ))
        #expect(image.width == 160)
        #expect(image.height == 100)
        let pixels = try #require(HorizonRenderer.pixels(
            frame: frame, bandPhase: 0.3, pixelWidth: 160, pixelHeight: 100
        ))
        // Row 0 of the buffer is the top of the image; the last row is ground.
        let ground = HorizonPalette.ground(elevation: frame.elevation).bytes
        let last = (99 * 160 + 80) * 4
        #expect(Array(pixels[last ..< last + 3]) == ground)
        #expect(pixels[last + 3] == 255)
    }
}
