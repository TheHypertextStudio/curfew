import AppKit
import CurfewKit
import SwiftUI

/// Routes app navigation through actions supplied by available SwiftUI scenes,
/// retaining early requests until a scene can handle them.
///
/// Production builds use `SystemAppRouter`; tests substitute a spy implementing
/// this protocol to assert activation and navigation in isolation.
@MainActor
protocol AppRouting: AnyObject {
    /// Brings Curfew to the foreground, activating it regardless of whether
    /// another app currently owns focus. Required before showing any window
    /// so the window actually surfaces in front of the user.
    func activate()

    /// Supplies the Settings action from an active SwiftUI scene and fulfills
    /// any request made before that scene appeared.
    func registerSettingsOpener(_ opener: @escaping @MainActor () -> Void)

    /// Invokes the Settings action registered by the visible scene.
    func showSettings()

    /// Supplies named-window actions without requiring the main workspace.
    func registerWindowActions(
        open: @escaping @MainActor (String) -> Void,
        dismiss: @escaping @MainActor (String) -> Void
    )

    /// Opens or focuses a named window, retaining an early request.
    func openWindow(id: String)
    /// Dismisses a named window, superseding any pending opening request.
    func dismissWindow(id: String)
}

/// Activates through AppKit and performs navigation through SwiftUI scene
/// actions. Repeated early requests coalesce to the last intent per window.
@MainActor
final class SystemAppRouter: AppRouting {
    private enum WindowAction {
        case open
        case dismiss
    }

    private var settingsOpener: (@MainActor () -> Void)?
    private var settingsOpenPending = false
    private var windowOpener: (@MainActor (String) -> Void)?
    private var windowDismisser: (@MainActor (String) -> Void)?
    private var pendingWindowActions: [String: WindowAction] = [:]

    /// Activates the Curfew process, ignoring which app currently holds focus.
    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerSettingsOpener(_ opener: @escaping @MainActor () -> Void) {
        settingsOpener = opener
        if settingsOpenPending {
            settingsOpenPending = false
            opener()
        }
    }

    /// Uses SwiftUI's scene action, coalescing early requests until one exists.
    /// `showSettingsWindow:` did not dispatch to this app's Settings scene on
    /// the hosted macOS runner.
    func showSettings() {
        guard let settingsOpener else {
            settingsOpenPending = true
            return
        }
        settingsOpener()
    }

    func registerWindowActions(
        open: @escaping @MainActor (String) -> Void,
        dismiss: @escaping @MainActor (String) -> Void
    ) {
        windowOpener = open
        windowDismisser = dismiss
        let pending = pendingWindowActions
        pendingWindowActions.removeAll()
        for (id, action) in pending {
            route(action, to: id)
        }
    }

    func openWindow(id: String) {
        route(.open, to: id)
    }

    func dismissWindow(id: String) {
        route(.dismiss, to: id)
    }

    private func route(_ action: WindowAction, to id: String) {
        guard let windowOpener, let windowDismisser else {
            pendingWindowActions[id] = action
            return
        }
        switch action {
        case .open: windowOpener(id)
        case .dismiss: windowDismisser(id)
        }
    }
}
