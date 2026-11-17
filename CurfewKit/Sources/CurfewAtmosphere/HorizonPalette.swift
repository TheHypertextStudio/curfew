import CurfewKit
import Foundation

/// An sRGB colour as fractions. Values may exceed 1 where the shader brightens
/// the sun disc; ``bytes`` clamps when writing pixels.
public struct HorizonRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func mixed(with other: HorizonRGB, _ amount: Double) -> HorizonRGB {
        HorizonRGB(
            mix(red, other.red, amount),
            mix(green, other.green, amount),
            mix(blue, other.blue, amount)
        )
    }

    func scaled(_ factor: Double) -> HorizonRGB {
        HorizonRGB(red * factor, green * factor, blue * factor)
    }

    func offset(_ amount: Double) -> HorizonRGB {
        HorizonRGB(red + amount, green + amount, blue + amount)
    }

    /// 8-bit sRGB channels (red, green, blue), clamped and rounded.
    public var bytes: [UInt8] {
        [red, green, blue].map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
    }
}

/// One complete sky: the five-stop ramps that colour each brightness step,
/// chosen by elevation, the flat ground below the horizon at each of the same
/// four moments, and the moon's two faces. Stops run from far sky (0) to
/// nearest the light (4).
///
/// Every palette is drawn by the same field in the same stepped hand; only the
/// colours change. ``standard`` is the spec table. The Metal shader reads the
/// palette through ``shaderTable`` and the CPU renderer reads it directly, so
/// both draw the same picture for every palette.
public struct HorizonPalette: Equatable, Sendable {
    public var day: [HorizonRGB]
    public var lastHour: [HorizonRGB]
    public var dusk: [HorizonRGB]
    public var night: [HorizonRGB]

    public var dayGround: HorizonRGB
    public var lastHourGround: HorizonRGB
    public var duskGround: HorizonRGB
    public var nightGround: HorizonRGB

    /// The moon's lit and unlit faces.
    public var moonLit: HorizonRGB
    public var moonDark: HorizonRGB

    /// - Parameters:
    ///   - grounds: the flat ground at day, the last hour, dusk and night.
    ///   - moonLit: the moon's lit face; `moonDark` its unlit face.
    public init(
        day: [HorizonRGB], lastHour: [HorizonRGB], dusk: [HorizonRGB], night: [HorizonRGB],
        grounds: [HorizonRGB], moonLit: HorizonRGB, moonDark: HorizonRGB
    ) {
        precondition(
            [day, lastHour, dusk, night].allSatisfy { $0.count == 5 } && grounds.count == 4,
            "Each ramp has five stops and there are four grounds"
        )
        self.day = day
        self.lastHour = lastHour
        self.dusk = dusk
        self.night = night
        self.dayGround = grounds[0]
        self.lastHourGround = grounds[1]
        self.duskGround = grounds[2]
        self.nightGround = grounds[3]
        self.moonLit = moonLit
        self.moonDark = moonDark
    }

    /// The sky a saved choice draws.
    public init(_ choice: RestAppearancePreferences.Palette) {
        switch choice {
        case .sundown: self = .standard
        case .warmAmber: self = .desert
        case .coolTwilight: self = .polar
        }
    }

    // MARK: Shader

    /// How many floats ``shaderTable`` holds, and how many the shader requires.
    public static let shaderTableCount = 78

    /// The table the Metal shader reads, so the GPU and this CPU port share
    /// one source: for each of six stops (the five ramp stops, then the
    /// ground), the day, last-hour, dusk and night colours as RGB floats;
    /// then the moon's lit and unlit faces.
    public var shaderTable: [Float] {
        let grounds = [dayGround, lastHourGround, duskGround, nightGround]
        var table: [Float] = []
        table.reserveCapacity(Self.shaderTableCount)
        for stop in 0 ..< 6 {
            let colors = stop < 5
                ? [day[stop], lastHour[stop], dusk[stop], night[stop]]
                : grounds
            for color in colors {
                table += [Float(color.red), Float(color.green), Float(color.blue)]
            }
        }
        for color in [moonLit, moonDark] {
            table += [Float(color.red), Float(color.green), Float(color.blue)]
        }
        return table
    }

    // MARK: Sampling

    /// The shader's `ph`: blend the four palettes by elevation. Above 0.1 the
    /// last hour warms into day; around the horizon dusk turns to the last
    /// hour; below it night deepens.
    static func blend(
        day: HorizonRGB, lastHour: HorizonRGB, dusk: HorizonRGB, night: HorizonRGB,
        elevation: Double
    ) -> HorizonRGB {
        if elevation > 0.1 {
            return lastHour.mixed(with: day, smoothstep(0.1, 0.55, elevation))
        }
        if elevation > -0.05 {
            return dusk.mixed(with: lastHour, smoothstep(-0.05, 0.1, elevation))
        }
        return night.mixed(with: dusk, smoothstep(-0.4, -0.05, elevation))
    }

    /// The shader's `ramp`: the colour at `position` (0 far sky, 1 nearest
    /// the light) for an elevation.
    public func ramp(_ position: Double, elevation: Double) -> HorizonRGB {
        let stops = (0 ..< 5).map { index in
            Self.blend(
                day: day[index], lastHour: lastHour[index], dusk: dusk[index],
                night: night[index], elevation: elevation
            )
        }
        let scaled = min(max(position, 0), 1) * 4
        let lower = min(Int(scaled), 3)
        return stops[lower].mixed(with: stops[lower + 1], scaled - Double(lower))
    }

    /// The flat ground colour for an elevation.
    public func ground(elevation: Double) -> HorizonRGB {
        Self.blend(
            day: dayGround, lastHour: lastHourGround, dusk: duskGround, night: nightGround,
            elevation: elevation
        )
    }
}

// MARK: - Authored palettes

public extension HorizonPalette {
    /// Sundown, the default: a clear blue day, a violet and gold last hour, a
    /// plum dusk and an indigo night. The spec table.
    static let standard = HorizonPalette(
        day: [
            HorizonRGB(0.10, 0.27, 0.66), HorizonRGB(0.22, 0.44, 0.82),
            HorizonRGB(0.44, 0.64, 0.91), HorizonRGB(0.70, 0.82, 0.95),
            HorizonRGB(0.94, 0.96, 0.98)
        ],
        lastHour: [
            HorizonRGB(0.15, 0.17, 0.46), HorizonRGB(0.38, 0.27, 0.60),
            HorizonRGB(0.74, 0.38, 0.55), HorizonRGB(0.95, 0.56, 0.27),
            HorizonRGB(1.0, 0.84, 0.52)
        ],
        dusk: [
            HorizonRGB(0.07, 0.08, 0.24), HorizonRGB(0.20, 0.15, 0.42),
            HorizonRGB(0.50, 0.22, 0.45), HorizonRGB(0.83, 0.34, 0.30),
            HorizonRGB(0.96, 0.62, 0.30)
        ],
        night: [
            HorizonRGB(0.027, 0.031, 0.094), HorizonRGB(0.047, 0.059, 0.165),
            HorizonRGB(0.10, 0.12, 0.31), HorizonRGB(0.135, 0.155, 0.37),
            HorizonRGB(0.19, 0.21, 0.46)
        ],
        grounds: [
            HorizonRGB(0.07, 0.11, 0.29), HorizonRGB(0.11, 0.085, 0.25),
            HorizonRGB(0.065, 0.05, 0.18), HorizonRGB(0.018, 0.02, 0.055)
        ],
        moonLit: HorizonRGB(0.93, 0.92, 0.97), moonDark: HorizonRGB(0.2, 0.22, 0.42)
    )

    /// Desert: a dusty, sun-bleached day over red earth, a terracotta and
    /// amber last hour, a wine-dark dusk and a warm aubergine night under an
    /// ivory moon.
    static let desert = HorizonPalette(
        day: [
            HorizonRGB(0.15, 0.35, 0.62), HorizonRGB(0.33, 0.55, 0.77),
            HorizonRGB(0.65, 0.78, 0.86), HorizonRGB(0.95, 0.89, 0.75),
            HorizonRGB(1.0, 0.97, 0.86)
        ],
        lastHour: [
            HorizonRGB(0.22, 0.13, 0.30), HorizonRGB(0.49, 0.20, 0.32),
            HorizonRGB(0.80, 0.34, 0.23), HorizonRGB(0.95, 0.57, 0.22),
            HorizonRGB(1.0, 0.82, 0.48)
        ],
        dusk: [
            HorizonRGB(0.11, 0.055, 0.14), HorizonRGB(0.27, 0.09, 0.22),
            HorizonRGB(0.54, 0.16, 0.23), HorizonRGB(0.80, 0.29, 0.18),
            HorizonRGB(0.94, 0.52, 0.24)
        ],
        night: [
            HorizonRGB(0.050, 0.028, 0.055), HorizonRGB(0.10, 0.052, 0.10),
            HorizonRGB(0.19, 0.095, 0.18), HorizonRGB(0.27, 0.135, 0.24),
            HorizonRGB(0.38, 0.19, 0.32)
        ],
        grounds: [
            HorizonRGB(0.22, 0.11, 0.09), HorizonRGB(0.17, 0.075, 0.09),
            HorizonRGB(0.10, 0.04, 0.07), HorizonRGB(0.024, 0.012, 0.022)
        ],
        moonLit: HorizonRGB(0.98, 0.93, 0.83), moonDark: HorizonRGB(0.25, 0.14, 0.21)
    )

    /// Polar: a cold teal day over deep water, a pale rose and lilac last
    /// hour, a slate dusk and a blue-black night that turns green around the
    /// moon.
    static let polar = HorizonPalette(
        day: [
            HorizonRGB(0.05, 0.29, 0.47), HorizonRGB(0.14, 0.49, 0.63),
            HorizonRGB(0.40, 0.71, 0.79), HorizonRGB(0.71, 0.88, 0.90),
            HorizonRGB(0.94, 0.98, 0.98)
        ],
        lastHour: [
            HorizonRGB(0.16, 0.22, 0.40), HorizonRGB(0.35, 0.37, 0.58),
            HorizonRGB(0.58, 0.47, 0.67), HorizonRGB(0.85, 0.61, 0.70),
            HorizonRGB(1.0, 0.88, 0.80)
        ],
        dusk: [
            HorizonRGB(0.04, 0.09, 0.18), HorizonRGB(0.08, 0.19, 0.30),
            HorizonRGB(0.21, 0.31, 0.45), HorizonRGB(0.53, 0.45, 0.58),
            HorizonRGB(0.85, 0.63, 0.62)
        ],
        night: [
            HorizonRGB(0.020, 0.050, 0.080), HorizonRGB(0.035, 0.10, 0.13),
            HorizonRGB(0.060, 0.19, 0.21), HorizonRGB(0.090, 0.28, 0.27),
            HorizonRGB(0.14, 0.39, 0.34)
        ],
        grounds: [
            HorizonRGB(0.03, 0.13, 0.20), HorizonRGB(0.08, 0.10, 0.22),
            HorizonRGB(0.03, 0.055, 0.13), HorizonRGB(0.008, 0.022, 0.035)
        ],
        moonLit: HorizonRGB(0.90, 0.97, 0.96), moonDark: HorizonRGB(0.08, 0.19, 0.23)
    )

    /// Every palette Curfew ships, in the order the editor lists them.
    static let all: [HorizonPalette] = [.standard, .desert, .polar]
}
