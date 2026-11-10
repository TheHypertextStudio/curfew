import AppKit
@testable import Curfew
import Testing

@MainActor
struct RestWindowBackingTests {
    @Test("Rest scenes retain an opaque native backing beneath the sky and reveal")
    func restWindowsHaveOpaqueBacking() {
        let coordinator = OverlayCoordinator()
        for configuration in [
            OverlayCoordinator.lockoutWindowConfiguration,
            OverlayCoordinator.daybreakWindowConfiguration
        ] {
            let window = makeWindow()
            defer { window.orderOut(nil) }
            coordinator.apply(configuration: configuration, to: window)
            #expect(window.isOpaque)
            #expect(window.backgroundColor == .black)
            #expect(window.alphaValue == 1)
        }
    }

    @Test("Warning overlays preserve their transparent, click-through backing")
    func warningsRemainTransparent() {
        let window = makeWindow()
        defer { window.orderOut(nil) }
        OverlayCoordinator().apply(
            configuration: OverlayCoordinator.warningWindowConfiguration, to: window
        )
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.ignoresMouseEvents)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }
}
