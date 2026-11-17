import Foundation

/// Quiets the sky behind text that sits over it, inside the field itself, so
/// the result is still the sky's own hard-edged steps with no shape laid on top.
///
/// Two moves, applied to the brightness before it is cut into bands:
///
/// - **Glow.** The horizon's glow is taken out under the text, in a soft dome
///   that rests on the horizon and fades out to the sides and above the text.
///   The sun's own falloff is left alone, so its rings stay round.
/// - **Tone.** When the sun itself is close to the text, every level of the
///   sky is lowered together: brightness below `knee` is scaled by `scale`,
///   and the levels above it are stretched back up to full. Because the remap
///   is monotonic, every band keeps the shape it had; there are only fewer
///   bands below the knee and more, finer ones near the sun.
///
/// ``none`` changes nothing. `HorizonSky.metal` applies the same arithmetic;
/// keep the two in step.
public struct HorizonHush: Equatable, Sendable {
    /// The centre of the text block, in the scene's unit frame (y up).
    public var centre: HorizonPoint
    /// Half-widths of the dome's falloff, in units of the scene's height.
    public var radiusX: Double
    public var radiusY: Double
    /// The share of the horizon's glow removed at the centre, 0 to 1.
    public var glow: Double
    /// How much the levels below ``knee`` are scaled, 0 to 1. 1 leaves them.
    public var scale: Double
    /// The brightness up to which ``scale`` applies.
    public var knee: Double

    public init(
        centre: HorizonPoint, radiusX: Double, radiusY: Double, glow: Double, scale: Double,
        knee: Double
    ) {
        self.centre = centre
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.glow = glow
        self.scale = scale
        self.knee = knee
    }

    /// Leaves the sky exactly as the model draws it.
    public static let none = HorizonHush(
        centre: HorizonPoint(x: 0.5, y: 0.5), radiusX: 1, radiusY: 1, glow: 0, scale: 1, knee: 1
    )

    /// True when the hush changes nothing.
    public var isNone: Bool {
        glow <= 0 && scale >= 1
    }

    /// How strongly the glow is removed at a point: 1 from the centre down to
    /// the horizon, falling off as a Gaussian to the sides and above.
    public func weight(at point: HorizonPoint, aspect: Double) -> Double {
        guard glow > 0, radiusX > 0, radiusY > 0 else { return 0 }
        let across = (point.x - centre.x) * aspect / radiusX
        let above = max(point.y - centre.y, 0) / radiusY
        return exp(-(across * across + above * above))
    }

    /// The tone remap applied to a brightness level.
    public func toned(_ level: Double) -> Double {
        guard scale < 1 else { return level }
        if level <= knee {
            return level * scale
        }
        let lowered = knee * scale
        return lowered + (level - knee) * (1 - lowered) / max(1 - knee, 1e-4)
    }

    /// The values the shader reads: the dome's shape (centre x, centre y,
    /// radius x, radius y) and its tone (glow, scale, knee).
    public var shaderShape: [Float] {
        [Float(centre.x), Float(centre.y), Float(radiusX), Float(radiusY)]
    }

    public var shaderTone: [Float] {
        [Float(glow), Float(scale), Float(knee)]
    }
}
