import AppKit
import CurfewAtmosphere
import CurfewKit
import ScreenSaver
import SwiftUI

/// The native host owns cadence; every rendered frame resolves from absolute time.
@objc(CurfewScreenSaverView)
final class CurfewScreenSaverView: ScreenSaverView {
    private var hostedScene: NSHostingView<RestAmbientScene>?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
    }

    override func startAnimation() {
        super.startAnimation()
        refresh(at: Date())
    }

    override func stopAnimation() {
        super.stopAnimation()
        hostedScene?.removeFromSuperview()
        hostedScene = nil
    }

    override func animateOneFrame() {
        guard isAnimating else { return }
        refresh(at: Date())
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostedScene?.frame = bounds
    }

    private func refresh(at date: Date) {
        // No occurrence or message is inferred before the separate export bridge is integrated.
        let snapshot = RestSceneSnapshot(
            version: 1,
            expiresAt: date.addingTimeInterval(60),
            appearance: RestAppearancePreferences(),
            lockDate: nil,
            unlockDate: nil
        )
        let scene = RestAmbientScene(
            snapshot: snapshot,
            date: date,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            clockSize: max(20, min(bounds.width, bounds.height) * 0.10),
            showsMessage: false
        )
        if let hostedScene {
            hostedScene.rootView = scene
            hostedScene.frame = bounds
        } else {
            let host = NSHostingView(rootView: scene)
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            hostedScene = host
        }
    }
}
