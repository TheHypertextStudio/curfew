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

/// The five-stop ramps that colour each brightness step, chosen by elevation,
/// and the flat ground below the horizon. Stops run from far sky (0) to
/// nearest the light (4). Values are the spec table, as sRGB fractions.
public enum HorizonPalette {
    public static let day = [
        HorizonRGB(0.10, 0.27, 0.66), HorizonRGB(0.22, 0.44, 0.82),
        HorizonRGB(0.44, 0.64, 0.91), HorizonRGB(0.70, 0.82, 0.95),
        HorizonRGB(0.94, 0.96, 0.98)
    ]
    public static let lastHour = [
        HorizonRGB(0.15, 0.17, 0.46), HorizonRGB(0.38, 0.27, 0.60),
        HorizonRGB(0.74, 0.38, 0.55), HorizonRGB(0.95, 0.56, 0.27),
        HorizonRGB(1.0, 0.84, 0.52)
    ]
    public static let dusk = [
        HorizonRGB(0.07, 0.08, 0.24), HorizonRGB(0.20, 0.15, 0.42),
        HorizonRGB(0.50, 0.22, 0.45), HorizonRGB(0.83, 0.34, 0.30),
        HorizonRGB(0.96, 0.62, 0.30)
    ]
    public static let night = [
        HorizonRGB(0.027, 0.031, 0.094), HorizonRGB(0.047, 0.059, 0.165),
        HorizonRGB(0.10, 0.12, 0.31), HorizonRGB(0.135, 0.155, 0.37),
        HorizonRGB(0.19, 0.21, 0.46)
    ]

    public static let dayGround = HorizonRGB(0.07, 0.11, 0.29)
    public static let lastHourGround = HorizonRGB(0.11, 0.085, 0.25)
    public static let duskGround = HorizonRGB(0.065, 0.05, 0.18)
    public static let nightGround = HorizonRGB(0.018, 0.02, 0.055)

    /// The moon's lit and unlit faces.
    public static let moonLit = HorizonRGB(0.93, 0.92, 0.97)
    public static let moonDark = HorizonRGB(0.2, 0.22, 0.42)

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
    public static func ramp(_ position: Double, elevation: Double) -> HorizonRGB {
        let stops = (0 ..< 5).map { index in
            blend(
                day: day[index], lastHour: lastHour[index], dusk: dusk[index],
                night: night[index], elevation: elevation
            )
        }
        let scaled = min(max(position, 0), 1) * 4
        let lower = min(Int(scaled), 3)
        return stops[lower].mixed(with: stops[lower + 1], scaled - Double(lower))
    }

    /// The table the Metal shader reads, so the GPU and this CPU port share
    /// one source: for each of six stops (the five ramp stops, then the
    /// ground), the day, last-hour, dusk and night colours as RGB floats.
    public static var shaderTable: [Float] {
        let grounds = [dayGround, lastHourGround, duskGround, nightGround]
        var table: [Float] = []
        table.reserveCapacity(72)
        for stop in 0 ..< 6 {
            let colors = stop < 5
                ? [day[stop], lastHour[stop], dusk[stop], night[stop]]
                : grounds
            for color in colors {
                table += [Float(color.red), Float(color.green), Float(color.blue)]
            }
        }
        return table
    }

    /// The flat ground colour for an elevation.
    public static func ground(elevation: Double) -> HorizonRGB {
        blend(
            day: dayGround, lastHour: lastHourGround, dusk: duskGround, night: nightGround,
            elevation: elevation
        )
    }
}
