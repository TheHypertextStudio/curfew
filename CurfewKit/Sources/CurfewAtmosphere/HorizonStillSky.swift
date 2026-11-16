import CoreGraphics
import SwiftUI

/// The Horizon scene drawn once on the CPU by ``HorizonRenderer``. Used where
/// the Metal shader cannot run (the headless snapshot harness, the widget,
/// exported images) and as the default sky of ``RestAmbientScene`` in tests.
/// It does not animate; hosts that want drifting bands use the app's shader view.
@available(macOS 26.0, *)
public struct HorizonStillSky: View {
    public var frame: HorizonFrame
    public var bandPhase: Double
    @Environment(\.displayScale) private var displayScale

    public init(frame: HorizonFrame, bandPhase: Double = HorizonBandPhase.resting) {
        self.frame = frame
        self.bandPhase = bandPhase
    }

    public var body: some View {
        GeometryReader { proxy in
            let scale = max(displayScale, 1)
            if let image = HorizonRenderer.image(
                frame: frame, bandPhase: bandPhase,
                pixelWidth: max(1, Int((proxy.size.width * scale).rounded())),
                pixelHeight: max(1, Int((proxy.size.height * scale).rounded()))
            ) {
                Image(decorative: image, scale: scale)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color(
                    red: HorizonPalette.nightGround.red,
                    green: HorizonPalette.nightGround.green,
                    blue: HorizonPalette.nightGround.blue
                )
            }
        }
        .accessibilityHidden(true)
    }
}
