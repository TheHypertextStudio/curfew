import AppKit

/// Borderless `NSWindow` instances are not key-eligible by default. The
/// morning form needs a key window for its text editor and keyboard controls.
private final class DaybreakOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
extension OverlayCoordinator {
    static func makeDaybreakWindow(frame: NSRect, screen: NSScreen?) -> NSWindow {
        DaybreakOverlayWindow(
            contentRect: frame,
            styleMask: daybreakWindowConfiguration.styleMask,
            backing: .buffered,
            defer: false,
            screen: screen
        )
    }

    /// A tick must not replace the hosting view: its reflection form owns
    /// unsaved answers and text focus in SwiftUI `@State`.
    static func reconcileExistingDaybreakWindow(_ window: NSWindow, frame: NSRect) {
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }
}
