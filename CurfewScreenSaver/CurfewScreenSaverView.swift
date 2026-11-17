import AppKit
import CurfewAtmosphere
import CurfewKit
import ScreenSaver
import SwiftUI

/// The native host owns cadence; every rendered frame resolves from absolute time.
@objc(CurfewScreenSaverView)
final class CurfewScreenSaverView: ScreenSaverView {
    private var hostedScene: NSHostingView<RestAmbientScene<HorizonSkyView>>?
    private var session: RestScreenSaverSession?
    private var lastPreferenceRead: Date?
    private var rendering = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
    }

    override static func performGammaFade() -> Bool {
        true
    }

    override func startAnimation() {
        super.startAnimation()
        session?.stop()
        session = nil
        lastPreferenceRead = nil
        rendering = true
        refresh(at: Date())
    }

    override func stopAnimation() {
        rendering = false
        super.stopAnimation()
        session?.stop()
        session = nil
        lastPreferenceRead = nil
        hostedScene?.removeFromSuperview()
        hostedScene = nil
    }

    override func animateOneFrame() {
        guard rendering, isAnimating else { return }
        refresh(at: Date())
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hostedScene?.frame = bounds
    }

    private func refreshPreferencesIfNeeded(at date: Date) {
        // The native host supplies cadence. Read potentially large preferences at most
        // once a second; rendering still resolves every frame from the absolute date.
        if let lastPreferenceRead, date >= lastPreferenceRead,
           date.timeIntervalSince(lastPreferenceRead) < 1 {
            return
        }
        lastPreferenceRead = date
        if let session {
            _ = session.frame(at: date, timeZone: .current)
        } else if let preferences = try? RestScreenSaverPreferences
            .companionSystem(isPreview: isPreview) {
            let session = RestScreenSaverSession(
                preferences: preferences,
                decodeImage: RestScreenSaverPreferences.boundedImage
            )
            self.session = session
            session.start(at: date)
        }
    }

    /// The lock's night for the published occurrence, as the app draws it.
    static func lockFrame(snapshot: RestSceneSnapshot, at date: Date) -> HorizonFrame? {
        guard let lock = snapshot.lockDate, let unlock = snapshot.unlockDate,
              lock < unlock, date >= lock, date < unlock else { return nil }
        return LockSceneSky.frame(
            for: HorizonMoment.scheduled(now: date, curfew: lock, nextUnlock: unlock)
        )
    }

    private func refresh(at date: Date) {
        refreshPreferencesIfNeeded(at: date)
        let snapshot = session?.snapshot ?? RestSceneSnapshot(
            version: 1,
            expiresAt: date.addingTimeInterval(60),
            appearance: RestAppearancePreferences(),
            lockDate: nil,
            unlockDate: nil
        )
        let scene = RestAmbientScene(
            snapshot: snapshot,
            date: date,
            image: session?.image,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            clockSize: max(20, min(bounds.width, bounds.height) * 0.10),
            // The export allowlist has already applied separate message consent.
            showsMessage: true
        ) { frame, drifts in
            // The same Horizon scene as the app's lock, from the same model
            // and this bundle's shader, so a handoff shows one continuous sky.
            HorizonSkyView(
                frame: Self.lockFrame(snapshot: snapshot, at: date) ?? frame,
                isDayRunning: drifts
            )
        }
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
