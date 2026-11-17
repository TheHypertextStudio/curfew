import CurfewAtmosphere
import SwiftUI

/// How the sky is drawn. On screen the Metal shader draws it; the headless
/// snapshot harness, which rasterises views without a GPU compositor, uses the
/// CPU reference renderer so captures show the real scene.
enum HorizonSkyRendering: Sendable {
    case shader
    case reference
}

extension EnvironmentValues {
    /// Which renderer ``HorizonSkyView`` uses. Defaults to the shader.
    @Entry var horizonSkyRendering: HorizonSkyRendering = .shader
}

/// The Horizon scene: hard-edged steps of light around the sun or moon over a
/// flat ground. Driven by a ``HorizonFrame`` from the model. The bands drift
/// 0.05 per second only while `isDayRunning` is true; they hold still when the
/// day is not running and under Reduce Motion.
///
/// This file is compiled into both the app and the screen saver bundle, so it
/// must depend only on SwiftUI and CurfewAtmosphere. The shader comes from the
/// bundled `HorizonSky.metallib`; if it cannot load, the CPU image is drawn.
struct HorizonSkyView: View {
    var frame: HorizonFrame
    var isDayRunning: Bool
    /// How the sky is quieted behind text at a given size; nothing by default.
    var hush: (CGSize) -> HorizonHush

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizonSkyRendering) private var rendering
    @Environment(\.horizonPalette) private var palette
    @State private var bands = HorizonBandPhase(anchor: Date(), isRunning: false)

    init(
        frame: HorizonFrame, isDayRunning: Bool,
        hush: @escaping (CGSize) -> HorizonHush = { _ in .none }
    ) {
        self.frame = frame
        self.isDayRunning = isDayRunning
        self.hush = hush
    }

    private var isRunning: Bool {
        HorizonBandPhase.isRunning(dayIsRunning: isDayRunning, reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            let quiet = hush(proxy.size)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRunning)) { context in
                scene(size: proxy.size, phase: bands.value(at: context.date), hush: quiet)
            }
        }
        .onAppear { bands = bands.updating(isRunning: isRunning, at: Date()) }
        .onChange(of: isRunning) { _, running in
            bands = bands.updating(isRunning: running, at: Date())
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scene(size: CGSize, phase: Double, hush: HorizonHush) -> some View {
        switch rendering {
        case .shader where HorizonShaderLibrary.shared != nil:
            Rectangle()
                .fill(.black)
                .colorEffect(Self.shader(
                    frame: frame,
                    size: size,
                    phase: phase,
                    scale: displayScale,
                    palette: palette,
                    hush: hush
                ))
        case .shader, .reference:
            // Also the fallback when the bundled shader library cannot load.
            HorizonStillSky(frame: frame, bandPhase: phase, hush: hush)
        }
    }

    /// The SwiftUI shader for one frame in `palette`, from the bundled library.
    static func shader(
        frame: HorizonFrame, size: CGSize, phase: Double, scale: CGFloat,
        palette: HorizonPalette = .standard, hush: HorizonHush = .none
    ) -> Shader {
        let shape = hush.shaderShape
        let tone = hush.shaderTone
        return (HorizonShaderLibrary.shared?.library ?? .default).horizonSky(
            .float2(size),
            .float2(frame.sun.x, frame.sun.y),
            .float2(frame.moon.x, frame.moon.y),
            .float2(frame.sunWeight, frame.moonWeight),
            .float(frame.elevation),
            .float(phase),
            .float(frame.moonPhase),
            .float(scale),
            .float4(shape[0], shape[1], shape[2], shape[3]),
            .float3(tone[0], tone[1], tone[2]),
            .floatArray(palette.shaderTable)
        )
    }
}
