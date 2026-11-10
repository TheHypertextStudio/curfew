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
@MainActor
final class RestWindowStore {
    private(set) var windows: [CGDirectDisplayID: NSWindow] = [:]

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
