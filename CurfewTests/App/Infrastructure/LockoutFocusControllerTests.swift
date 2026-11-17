import AppKit
@testable import Curfew
import Foundation
import Testing

/// Drives ``LockoutFocusController`` against a private notification center and
/// recording system calls, so no test activates the real app, changes the real
/// presentation options, or unhides anything.
@MainActor
struct LockoutFocusControllerTests {
    private final class SystemSpy {
        var activations = 0
        var unhides = 0
        var options: NSApplication.PresentationOptions = [.autoHideDock]
        var optionWrites: [NSApplication.PresentationOptions] = []
    }

    private func makeController(
        spy: SystemSpy,
        center: NotificationCenter,
        holdsFocus: @escaping () -> Bool = { true },
        onScreensChanged: @escaping () -> Void = {}
    ) -> LockoutFocusController {
        LockoutFocusController(
            center: center,
            system: LockoutFocusController.System(
                activate: { spy.activations += 1 },
                unhide: { spy.unhides += 1 },
                presentationOptions: { spy.options },
                setPresentationOptions: { spy.options = $0
                    spy.optionWrites.append($0)
                }
            ),
            holdsFocus: holdsFocus,
            onScreensChanged: onScreensChanged
        )
    }

    @Test("Showing lockout activates Curfew and applies kiosk presentation once")
    func engageActivatesAndAppliesKiosk() {
        let spy = SystemSpy()
        let controller = makeController(spy: spy, center: NotificationCenter())
        controller.engage()
        controller.engage()
        #expect(spy.activations == 1)
        #expect(spy.options == LockoutFocusController.kioskOptions)
        #expect(spy.options.contains(.disableProcessSwitching))
        #expect(spy.options.contains(.disableHideApplication))
        #expect(!spy.options.contains(.disableSessionTermination))
    }

    @Test("Each frontmost reassertion re-activates Curfew while enforcing")
    func reassertActivates() {
        let spy = SystemSpy()
        let controller = makeController(spy: spy, center: NotificationCenter())
        controller.reassert()
        #expect(spy.activations == 0)
        controller.engage()
        controller.reassert()
        #expect(spy.activations == 2)
    }

    @Test("Resigning active during enforcement takes focus back")
    func resignActiveReactivates() {
        let spy = SystemSpy()
        let center = NotificationCenter()
        let controller = makeController(spy: spy, center: center)
        controller.engage()
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(spy.activations == 2)
    }

    @Test("Focus is left alone while the rest screensaver owns the display")
    func yieldsToScreensaverHandoff() {
        let spy = SystemSpy()
        let center = NotificationCenter()
        var holds = true
        let controller = makeController(spy: spy, center: center, holdsFocus: { holds })
        controller.engage()
        holds = false
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        controller.reassert()
        #expect(spy.activations == 1)
    }

    @Test("Hiding the app during enforcement unhides it and takes focus back")
    func hideUnhides() {
        let spy = SystemSpy()
        let center = NotificationCenter()
        let controller = makeController(spy: spy, center: center)
        controller.engage()
        center.post(name: NSApplication.didHideNotification, object: nil)
        #expect(spy.unhides == 1)
        #expect(spy.activations == 2)
    }

    @Test("A display change during enforcement reconciles the overlay immediately")
    func screenChangeReconciles() {
        let spy = SystemSpy()
        let center = NotificationCenter()
        var reconciles = 0
        let controller = makeController(spy: spy, center: center) { reconciles += 1 }
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(reconciles == 0)
        controller.engage()
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(reconciles == 1)
    }

    @Test("Releasing restores the prior presentation and stops reacting")
    func releaseRestores() {
        let spy = SystemSpy()
        let center = NotificationCenter()
        var reconciles = 0
        let controller = makeController(spy: spy, center: center) { reconciles += 1 }
        controller.engage()
        controller.release()
        #expect(spy.options == [.autoHideDock])
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        center.post(name: NSApplication.didHideNotification, object: nil)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(spy.activations == 1)
        #expect(spy.unhides == 0)
        #expect(reconciles == 0)
        controller.release()
        #expect(spy.optionWrites.count == 2)
    }
}
