import AppKit
@testable import Curfew
import SwiftUI
import Testing

@MainActor
struct OverlayContinuityTests {
    @Test("Clock updates retain the actual window and SwiftUI host")
    func retainsHostAcrossTicks() throws {
        let windows = RestWindowStore()
        let display = RestDisplay(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        windows.reconcile(displays: [display], makeWindow: makeWindow)
        let original = try #require(windows.windows[1])
        let host = try #require(original.contentView)
        windows.reconcile(displays: [display], makeWindow: makeWindow)
        #expect(windows.windows[1] === original)
        #expect(windows.windows[1]?.contentView === host)
    }

    @Test("A disconnected display removes its retained overlay")
    func removesDisconnectedDisplay() {
        let windows = RestWindowStore()
        windows.reconcile(displays: [RestDisplay(id: 1, frame: .zero)], makeWindow: makeWindow)
        windows.reconcile(displays: [], makeWindow: makeWindow)
        #expect(windows.windows.isEmpty)
    }

    @Test("Rearranging a display changes its frame without replacing the host")
    func preservesHostOnRearrangement() throws {
        let windows = RestWindowStore()
        let first = RestDisplay(id: 1, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        windows.reconcile(displays: [first], makeWindow: makeWindow)
        let host = try #require(windows.windows[1]?.contentView)
        let moved = RestDisplay(id: 1, frame: NSRect(x: -800, y: 0, width: 800, height: 600))
        windows.reconcile(displays: [moved], makeWindow: makeWindow)
        #expect(windows.windows[1]?.frame == moved.frame)
        #expect(windows.windows[1]?.contentView === host)
    }

    private func makeWindow(_ display: RestDisplay) -> NSWindow {
        let window = NSWindow(
            contentRect: display.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: Text("A retained editor host"))
        return window
    }
}
