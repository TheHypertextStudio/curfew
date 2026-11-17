import AppKit

/// Stable native display identity and geometry, independent of NSScreen object lifetime.
struct RestDisplay: Equatable {
    let id: CGDirectDisplayID
    let frame: NSRect

    @MainActor
    static var connected: [RestDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { return nil }
            return RestDisplay(id: number.uint32Value, frame: screen.frame)
        }
    }
}

/// Owns native windows for exactly the attached displays. Reconciliation never
/// replaces a live content view, preserving SwiftUI state and text focus.
///
/// Leaving fades every window to the desktop before ordering it out. A lock
/// that returns during the fade gets fresh windows; the departing ones finish
/// fading underneath and go.
@MainActor
final class RestWindowStore {
    /// Fades `window` out over `duration` seconds, then calls `completion`.
    typealias Fade = @MainActor (NSWindow, TimeInterval, @escaping @MainActor () -> Void) -> Void

    private(set) var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var departing: [ObjectIdentifier: NSWindow] = [:]
    private let fade: Fade

    init(fade: @escaping Fade = RestWindowStore.animateAlpha) {
        self.fade = fade
    }

    var departingCount: Int {
        departing.count
    }

    static func animateAlpha(
        _ window: NSWindow, duration: TimeInterval, completion: @escaping @MainActor () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    /// Fades every window to the desktop, then orders it out.
    func leave(duration: TimeInterval) {
        let leaving = windows.values
        windows.removeAll()
        for window in leaving {
            let key = ObjectIdentifier(window)
            departing[key] = window
            // The lock has been released; the fading scene must not hold input.
            window.ignoresMouseEvents = true
            fade(window, duration) { [weak self] in
                window.orderOut(nil)
                window.alphaValue = 1
                self?.departing.removeValue(forKey: key)
            }
        }
    }

    func reconcile(displays: [RestDisplay], makeWindow: (RestDisplay) -> NSWindow) {
        let connected = Set(displays.map(\.id))
        for id in windows.keys where !connected.contains(id) {
            windows.removeValue(forKey: id)?.orderOut(nil)
        }
        for display in displays {
            if let window = windows[display.id] {
                if window.frame != display.frame {
                    window.setFrame(display.frame, display: true)
                }
            } else {
                windows[display.id] = makeWindow(display)
            }
        }
    }

    func removeAll() {
        for window in windows.values {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}
