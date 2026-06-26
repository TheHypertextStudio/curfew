import AppKit
import CurfewKit
import SwiftUI

/// Presents and dismisses the first-launch "Welcome to Curfew" onboarding
/// window. Split out of `CurfewAppModel` so unit tests can replace the
/// concrete window presenter with a spy — without this indirection, every
/// test touching `showGettingStarted()` would have to instantiate a real
/// AppKit window.
@MainActor
protocol GettingStartedPresenting: AnyObject {
    /// Shows the onboarding window, binding it to the given model. If the
    /// window is already visible, this brings it to the front instead of
    /// creating a second instance.
    func present(model: CurfewAppModel)

    /// Closes the onboarding window if it is open, leaving the app focused
    /// on whatever surface the user was on previously.
    func dismiss()
}

/// Production `GettingStartedPresenting` that manages a single AppKit window
/// hosting the SwiftUI onboarding view. The presenter retains its own
/// `NSWindowController` so the window survives being closed-and-reopened
/// without rebuilding the SwiftUI hierarchy.
///
/// `isReleasedWhenClosed = false` is load-bearing: AppKit's default is to
/// deallocate the window on close, which would crash the second time the
/// user opens onboarding. Setting it to `false` and clearing our controller
/// reference in `windowWillClose` yields the right lifecycle.
@MainActor
final class GettingStartedWindowPresenter: NSObject, GettingStartedPresenting, NSWindowDelegate {
    /// Retained controller for the onboarding window. `nil` when the window
    /// is not currently displayed.
    private var windowController: NSWindowController?

    /// Creates (or re-focuses) the onboarding window.
    ///
    /// - Parameter model: the app model used as the SwiftUI environment
    ///   object for the onboarding view hierarchy.
    func present(model: CurfewAppModel) {
        if let window = windowController?.window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = GettingStartedView().environmentObject(model)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Curfew"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 430))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
    }

    /// Closes the onboarding window. Safe to call when nothing is presented.
    func dismiss() {
        windowController?.close()
        windowController = nil
    }

    /// `NSWindowDelegate` hook that clears our controller reference when the
    /// user closes the window manually (e.g. via the red traffic-light
    /// button), so the next `present(model:)` creates a fresh window.
    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}
