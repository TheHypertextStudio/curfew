import AppKit

/// Keeps keyboard focus on the lockout while it is enforced.
///
/// The overlay covers every display, but covering is not owning input: without
/// activation, keystrokes still reach the app behind it. While engaged, this
/// activates Curfew, applies kiosk presentation options, takes focus back when
/// Curfew resigns active or is hidden, and asks the overlay to cover a display
/// the moment one is attached. It yields while the rest screensaver handoff
/// owns the display. All AppKit effects are injected so tests never
/// touch the running app.
@MainActor
final class LockoutFocusController {
    struct System {
        var activate: () -> Void
        var unhide: () -> Void
        var presentationOptions: () -> NSApplication.PresentationOptions
        var setPresentationOptions: (NSApplication.PresentationOptions) -> Void

        static var live: System {
            System(
                activate: { NSApp.activate(ignoringOtherApps: true) },
                unhide: { NSApp.unhide(nil) },
                presentationOptions: { NSApp.presentationOptions },
                setPresentationOptions: { NSApp.presentationOptions = $0 }
            )
        }
    }

    /// Hides the Dock and menu bar and disables app switching, hiding, the
    /// Apple menu, and Force Quit. Session termination stays available, so
    /// logout, restart, and shutdown still work.
    static let kioskOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication,
        .disableAppleMenu, .disableForceQuit
    ]

    private let center: NotificationCenter
    private let system: System
    private let onScreensChanged: () -> Void
    private let holdsFocus: () -> Bool
    private var observers: [NSObjectProtocol] = []
    private var restoredOptions: NSApplication.PresentationOptions = []
    private(set) var isEngaged = false

    init(
        center: NotificationCenter = .default,
        system: System = .live,
        holdsFocus: @escaping () -> Bool = { true },
        onScreensChanged: @escaping () -> Void
    ) {
        self.center = center
        self.system = system
        self.holdsFocus = holdsFocus
        self.onScreensChanged = onScreensChanged
    }

    /// Called when the lockout first shows. Idempotent.
    func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        restoredOptions = system.presentationOptions()
        system.activate()
        system.setPresentationOptions(Self.kioskOptions)
        observe(NSApplication.didResignActiveNotification) { $0.takeFocus() }
        observe(NSApplication.didHideNotification) {
            $0.system.unhide()
            $0.takeFocus()
        }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.onScreensChanged() }
    }

    /// Called on each frontmost reassertion.
    func reassert() {
        guard isEngaged else { return }
        takeFocus()
    }

    /// Called when the lockout is gone. Restores the presentation options that
    /// were in effect before it engaged.
    func release() {
        guard isEngaged else { return }
        isEngaged = false
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        system.setPresentationOptions(restoredOptions)
    }

    /// Yields while the rest screensaver owns the display.
    private func takeFocus() {
        guard holdsFocus() else { return }
        system.activate()
    }

    private func observe(
        _ name: Notification.Name,
        _ handler: @escaping (LockoutFocusController) -> Void
    ) {
        // AppKit posts these on the main thread; a nil queue runs the handler
        // synchronously there.
        observers
            .append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEngaged else { return }
                    handler(self)
                }
            })
    }
}
