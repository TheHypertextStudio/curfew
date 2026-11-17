import Foundation

/// The CPU evaluation of the Horizon field. It is a line-for-line port of the
/// prototype's fragment shader (`scene()`), and `Curfew/UI/Horizon/HorizonSky.metal`
/// is the same code for the GPU. Keep the three in step.
public enum HorizonField {
    /// Brightness at a point: the screen blend of a falloff around the sun, a
    /// falloff around the moon, and a falloff above the horizon that
    /// strengthens while the sun is low.
    public static func brightness(
        at point: HorizonPoint, aspect: Double, frame: HorizonFrame
    ) -> Double {
        let horizon = HorizonGeometry.horizon
        let above = max((point.y - horizon) / (1 - horizon), 0)
        let toSun = hypot((point.x - frame.sun.x) * aspect, point.y - frame.sun.y)
        let toMoon = hypot((point.x - frame.moon.x) * aspect, point.y - frame.moon.y)
        let low = 1 - smoothstep(0.05, 0.6, abs(frame.elevation))
        let sun = 1 - exp(-toSun * 2.4) * frame.sunWeight
        let moon = 1 - exp(-toMoon * 3.2) * frame.moonWeight * 0.7
        let sky = 1 - exp(-above * 3.2) * mix(0.34, 0.9, low)
        return 1 - sun * moon * sky
    }

    /// The step a brightness falls in, as a ramp position. `edgeWidth` is the
    /// anti-aliasing width in band units (the shader's clamped `fwidth`).
    public static func quantised(_ level: Double, bandPhase: Double, edgeWidth: Double) -> Double {
        let count = Double(HorizonGeometry.bandCount)
        let band = level * count + bandPhase
        let fraction = band - floor(band)
        let stepped = floor(band) + smoothstep(1 - edgeWidth, 1, fraction)
        return (stepped - bandPhase) / count
    }

    /// The shader's edge width from the screen-space rate of change of the
    /// band coordinate (`fwidth(level * 14)`).
    public static func edgeWidth(levelChangePerPixel: Double) -> Double {
        min(max(levelChangePerPixel * Double(HorizonGeometry.bandCount) * 1.1, 0), 0.45)
    }

    /// The surface being drawn: its width over height, and its height in
    /// device pixels (anti-aliasing is 1.5 pixels wide, as in the shader).
    public struct Canvas: Equatable, Sendable {
        public var aspect: Double
        public var pixelHeight: Double

        public init(aspect: Double, pixelHeight: Double) {
            self.aspect = aspect
            self.pixelHeight = pixelHeight
        }
    }

    /// Where the band edges fall: the drift phase and the anti-aliasing width
    /// in band units.
    public struct Bands: Equatable, Sendable {
        public var phase: Double
        public var edgeWidth: Double

        public init(phase: Double, edgeWidth: Double) {
            self.phase = phase
            self.edgeWidth = edgeWidth
        }
    }

    /// The final colour at a point, in `palette`.
    public static func color(
        at point: HorizonPoint, canvas: Canvas, frame: HorizonFrame, bands: Bands,
        palette: HorizonPalette = .standard
    ) -> HorizonRGB {
        palette.fieldColor(
            at: point, level: brightness(at: point, aspect: canvas.aspect, frame: frame),
            canvas: canvas, frame: frame, bands: bands
        )
    }
}

extension HorizonPalette {
    /// The final colour at a point whose brightness is already known, in
    /// this palette.
    func fieldColor(
        at point: HorizonPoint, level: Double, canvas: HorizonField.Canvas, frame: HorizonFrame,
        bands: HorizonField.Bands
    ) -> HorizonRGB {
        if point.y < HorizonGeometry.horizon {
            return ground(elevation: frame.elevation)
        }
        let aspect = canvas.aspect
        let step = HorizonField.quantised(level, bandPhase: bands.phase, edgeWidth: bands.edgeWidth)
        var color = ramp(step, elevation: frame.elevation + (step - 0.5) * 0.24)
        let edge = 1.5 / max(canvas.pixelHeight, 1)

        // The sun disc, in the brightest stop of a slightly higher sky.
        let toSun = hypot((point.x - frame.sun.x) * aspect, point.y - frame.sun.y)
        let radius = HorizonGeometry.sunRadius
        let disc = (1 - smoothstep(radius - edge, radius + edge, toSun))
            * (frame.sunWeight >= 0.01 ? 1 : 0)
        let sunColor = ramp(1, elevation: frame.elevation + 0.12)
            .scaled(1.02).offset(0.03)
        color = color.mixed(with: sunColor, disc)

        // The moon, with a terminator from the phase angle.
        let across = (point.x - frame.moon.x) * aspect / HorizonGeometry.moonRadius
        let upward = (point.y - frame.moon.y) / HorizonGeometry.moonRadius
        let squared = across * across + upward * upward
        let terminator = across * sin(frame.moonPhase) - sqrt(max(1 - squared, 0)) *
            cos(frame.moonPhase)
        let face = terminator >= 0 ? moonLit : moonDark
        let moonDisc = (1 - smoothstep(1 - edge * 40, 1 + edge * 40, squared))
            * smoothstep(0, 0.25, frame.moonWeight)
        return color.mixed(with: face, moonDisc)
    }
}
