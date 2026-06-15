import Foundation
import SwiftUI

/// The one living sky. Renders a complete atmosphere — gradient, the sun's
/// glow, a night star-field, and a depth vignette — purely from a `SkyMoment`,
/// so Today, the lockout, the sunrise, and the menu bar all breathe the same
/// air and shift together through the day. Replaces the four bespoke static
/// gradients the app used to carry.
///
/// It is alive: a `TimelineView` drives a slow glow breath and gentle star
/// twinkle. All ambient motion freezes under Reduce Motion (the timeline is
/// paused), leaving a still, correct frame. The view fills whatever space it is
/// given, so callers use it as a full-bleed background.
struct SundownSky: View {
    /// The atmosphere to render.
    var moment: SkyMoment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                stops: SundownPalette.skyStops(for: moment.light),
                startPoint: .top,
                endPoint: .bottom
            )

            TimelineView(.animation(
                minimumInterval: 1.0 / 24.0,
                paused: reduceMotion
            )) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { proxy in
                    ZStack {
                        sunGlow(seconds: seconds)
                        sunDisc(in: proxy.size, seconds: seconds)
                        starField(seconds: seconds)
                    }
                }
            }

            vignette
        }
    }

    // MARK: - Layers

    /// The sun's warm bloom — anchored at the horizon when the light is falling
    /// (dusk) and rising from the crown at dawn. Reddens and strengthens as the
    /// lock time nears, and breathes slowly so the field never sits dead still.
    private func sunGlow(seconds: Double) -> some View {
        let breath = 0.92 + 0.08 * sin(seconds * 0.4)
        return RadialGradient(
            colors: [
                SundownPalette.glowColor(proximity: moment.proximity)
                    .opacity(glowStrength * breath),
                .clear
            ],
            center: moment.rising ? .top : .bottom,
            startRadius: 0,
            endRadius: 620
        )
        .blendMode(.screen)
    }

    /// The sun itself — a soft luminous disc that rides the sky by the moment's
    /// `light`: high at midday, sinking to the horizon as the lock time nears,
    /// reddening with `proximity`, and setting (fading out) into night. The
    /// literal embodiment of "a sundown for your Mac." It bobs almost
    /// imperceptibly so it feels suspended, not pasted on.
    private func sunDisc(in size: CGSize, seconds: Double) -> some View {
        let visible = max(0, min(1, (moment.light - 0.32) / 0.4))
        let bob = sin(seconds * 0.3) * 3
        let verticalFraction = 1.02 - moment.light * 0.92
        let center = CGPoint(
            x: size.width * 0.72,
            y: size.height * verticalFraction + bob
        )
        let radius = min(size.width, size.height) * 0.085
        let sunColor = SundownPalette.glowColor(proximity: moment.proximity)
        return ZStack {
            Circle()
                .fill(sunColor)
                .frame(width: radius * 2.2, height: radius * 2.2)
                .blur(radius: radius * 0.6)
            Circle()
                .fill(sunColor.opacity(0.95))
                .frame(width: radius * 1.25, height: radius * 1.25)
                .blur(radius: 2)
        }
        .position(center)
        .opacity(visible * 0.9)
        .blendMode(.screen)
    }

    /// Stars, drawn only once the sky has darkened past dusk. Positions are
    /// deterministic (seeded by index); each twinkles on its own phase.
    private func starField(seconds: Double) -> some View {
        Canvas { context, size in
            guard moment.starOpacity > 0.01 else { return }
            for index in 0 ..< Self.starCount {
                let point = Self.starPoint(index, in: size)
                let radius = Self.starRadius(index)
                let twinkle = 0.65 + 0.35 * sin(seconds * 0.8 + Self.starPhase(index))
                let alpha = Self.starBaseOpacity(index) * twinkle * moment.starOpacity
                let rect = CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }

    /// A soft radial darkening at the edges for depth.
    private var vignette: some View {
        RadialGradient(
            colors: [.clear, .black.opacity(0.18)],
            center: .center,
            startRadius: 240,
            endRadius: 720
        )
        .blendMode(.multiply)
    }

    // MARK: - Tuning

    /// Glow opacity: strongest around the horizon (golden/dusk/dawn), quieter at
    /// flat midday and deep night, lifted further as the curfew closes in.
    private var glowStrength: Double {
        let horizonPeak = 1 - min(abs(moment.light - 0.5) / 0.5, 1) // 1 at horizon
        return 0.18 + 0.30 * horizonPeak + 0.22 * moment.proximity
    }

    // MARK: - Star-field data (deterministic)

    private static let starCount = 60

    /// Pseudo-random but stable position for star `index`, kept to the upper
    /// reaches of the sky where stars read against the dark crown.
    private static func starPoint(_ index: Int, in size: CGSize) -> CGPoint {
        CGPoint(
            x: hashed(index, salt: 17) * size.width,
            y: hashed(index, salt: 53) * size.height * 0.62
        )
    }

    private static func starRadius(_ index: Int) -> CGFloat {
        0.6 + 1.1 * hashed(index, salt: 91)
    }

    private static func starBaseOpacity(_ index: Int) -> Double {
        0.35 + 0.55 * hashed(index, salt: 7)
    }

    /// A per-star phase offset (0...2π) so they don't twinkle in unison.
    private static func starPhase(_ index: Int) -> Double {
        hashed(index, salt: 131) * 2 * .pi
    }

    /// A cheap deterministic hash → 0...1 (no `Math.random`, stable per index).
    private static func hashed(_ index: Int, salt: Int) -> Double {
        let value = (index &* 2_654_435_761 &+ salt &* 40503) & 0xFFFF
        return Double(value) / Double(0xFFFF)
    }
}
