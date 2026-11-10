import AppKit
@testable import Curfew
import Testing

@MainActor
struct RestWindowModalAccessibilityTests {
    @Test("Screen-covering rest windows expose their modal accessibility semantics")
    func restWindowsExposeModalAccessibility() {
        let coordinator = OverlayCoordinator()
        for configuration in [
            OverlayCoordinator.lockoutWindowConfiguration,
            OverlayCoordinator.daybreakWindowConfiguration
        ] {
            let window = OverlayCoordinator.makeDaybreakWindow(
                frame: NSRect(x: 0, y: 0, width: 32, height: 32), screen: nil
            )
            defer { window.orderOut(nil) }
            coordinator.apply(configuration: configuration, to: window)

            #expect(
                window.isAccessibilityModal(),
                "Screen-covering window must expose AXModal; actual \(window.isAccessibilityModal())"
            )
        }
    }

    @Test("Click-through warning and timer windows remain nonmodal for accessibility")
    func warningAndTimerRemainNonmodal() {
        let coordinator = OverlayCoordinator()
        for configuration in [
            OverlayCoordinator.warningWindowConfiguration,
            OverlayCoordinator.timerWindowConfiguration
        ] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
            defer { window.orderOut(nil) }
            coordinator.apply(configuration: configuration, to: window)

            #expect(!window.isAccessibilityModal())
        }
    }
}
