import AppKit

/// Swaps the app's Dock icon to match the time of day (``TimeOfDay``), so
/// Curfew's presence drifts dawn → day → dusk → night like the Curfew Flow
/// itself. The static bundle icon (Finder, Launchpad, the `.app`) stays the
/// dusk signature; this only re-skins the *running* app's Dock tile.
///
/// `NSObject` + a target/selector timer mirrors `CurfewAppModel`'s tick loop,
/// sidestepping the `@Sendable` closure constraints of the block-based timer.
/// The day-part changes only a few times a day, so a coarse 5-minute poll is
/// ample and nearly free; the icon is only reassigned when the phase actually
/// changes.
@MainActor
final class DockIconController: NSObject {
    /// The phase whose icon is currently installed, or `nil` before the first
    /// update. Guards against redundant `applicationIconImage` writes.
    private var current: TimeOfDay?

    /// Coarse poll timer. `nil` until ``start()``.
    private var timer: Timer?

    /// How often to re-check the time of day. The phase boundaries are hours
    /// apart, so five minutes keeps the transition tight without busy-work.
    private static let pollInterval: TimeInterval = 300

    /// `nonisolated` so the `AppDelegate` can hold one as a stored property
    /// without an actor-isolation dance — the body only calls `super.init()`.
    /// All the methods that touch `NSApp` are `@MainActor` and run on the main
    /// thread.
    override nonisolated init() {
        super.init()
    }

    /// Installs the current phase's icon immediately and begins polling.
    /// Safe to call once at launch; re-arming is a no-op-ish reset.
    func start() {
        update(for: Date())
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(handleTimer),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func handleTimer() {
        update(for: Date())
    }

    /// Installs the Dock icon for `date`'s phase if it differs from what's
    /// shown. Exposed (non-private) so tests / the app can drive it directly.
    func update(for date: Date) {
        let phase = TimeOfDay.at(date)
        guard phase != current else { return }
        current = phase
        if let image = NSImage(named: phase.dockIconAssetName) {
            NSApp.applicationIconImage = image
        }
    }

    deinit {
        timer?.invalidate()
    }
}
