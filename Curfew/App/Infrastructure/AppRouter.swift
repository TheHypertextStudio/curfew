import AppKit
import SwiftUI

/// Abstraction over "bring the app to focus and show settings" so tests can
/// verify that menu bar and in-app affordances route through the expected
/// navigation path without touching real `NSApp` APIs.
///
/// Production builds use `SystemAppRouter`; tests substitute a spy implementing
/// this protocol to assert activation + settings-window calls in isolation.
@MainActor
protocol AppRouting: AnyObject {
    /// Brings Curfew to the foreground, activating it regardless of whether
    /// another app currently owns focus. Required before showing any window
    /// so the window actually surfaces in front of the user.
    func activate()

    /// Supplies the Settings action from an active SwiftUI scene.
    func registerSettingsOpener(_ opener: @escaping @MainActor () -> Void)

    /// Invokes the Settings action registered by the visible scene.
    func showSettings()
}

/// Default `AppRouting` implementation that delegates to `NSApp`.
///
/// Kept as a tiny concrete type (rather than folding the two lines into the
/// caller) so tests can swap it out, and so the two routing actions live
/// together when we eventually add deep-link or URL-scheme handling.
@MainActor
final class SystemAppRouter: AppRouting {
    private var settingsOpener: (@MainActor () -> Void)?

    /// Activates the Curfew process, ignoring which app currently holds focus.
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerSettingsOpener(_ opener: @escaping @MainActor () -> Void) {
        settingsOpener = opener
    }

    /// Uses SwiftUI's scene action. `showSettingsWindow:` did not dispatch to
    /// this app's Settings scene on the hosted macOS runner.
    func showSettings() {
        settingsOpener?()
    }
}
