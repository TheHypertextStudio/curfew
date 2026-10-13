import AppKit
@testable import Curfew
import Testing

@MainActor
struct DaybreakOverlayReconciliationTests {
    @Test("The borderless daybreak window can become key for text input")
    func daybreakWindowAcceptsKeyboardFocus() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = OverlayCoordinator.makeDaybreakWindow(frame: frame, screen: nil)
        defer { window.orderOut(nil) }

        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
    }

    @Test("A daybreak tick preserves the existing form view")
    func existingWindowKeepsContent() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: frame)
        window.contentView = content
        defer { window.orderOut(nil) }

        OverlayCoordinator.reconcileExistingDaybreakWindow(window, frame: frame)

        #expect(window.contentView === content)
        #expect(window.frame == frame)
    }
}
