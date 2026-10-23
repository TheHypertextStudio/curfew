import AppKit
import CurfewKit
import Foundation

/// AppKit application delegate for Curfew.
///
/// SwiftUI's `App` lifecycle owns launch and scene composition; the delegate's
/// one job is to re-assert enforcement when the user returns to the Mac. On app
/// activation it re-polls Accessibility trust + tap liveness and, when locked,
/// restarts the keyboard shield and re-fronts the lockout overlay so a degraded
/// lockout recovers. System wake is handled by the model's own
/// `NSWorkspace` observers (see `CurfewAppModel.startEnforcementReassertionObservers`).
///
/// The shared model is injected by `CurfewApp.init` after the scene graph is
/// constructed; it is `weak` so the delegate never keeps the model alive past
/// the app's own lifetime.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live app model, injected by `CurfewApp`. `weak` so the delegate
    /// observes rather than owns the model.
    weak var model: CurfewAppModel?
    var openMainWindow: (() -> Void)?
    var backgroundLaunch = CurfewLaunchBehavior.isBackgroundLaunch(
        arguments: ProcessInfo.processInfo.arguments
    )
    var activationProbe: () -> Bool = { NSApplication.shared.isActive }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        !backgroundLaunch
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if !backgroundLaunch || activationProbe() {
            openMainWindow?()
        } else {
            // Foreground opens activate after this callback; launchd recovery stays inactive.
            DispatchQueue.main.async { [weak self] in
                guard let self, activationProbe() else { return }
                openMainWindow?()
            }
        }
        return false
    }

    private let callbackRouter: any AccountOAuthCallbackRouting

    override convenience init() {
        self.init(callbackRouter: AccountOAuthCallbackRouter.shared)
    }

    init(callbackRouter: any AccountOAuthCallbackRouting) {
        self.callbackRouter = callbackRouter
        super.init()
    }

    /// Universal-link callbacks from another browser profile are accepted only
    /// for the exact pending claimed-HTTPS OAuth transaction.
    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            if callbackRouter.route(url) || model?.handleLicenseActivationURL(url) == true {
                break
            }
        }
    }

    /// Claimed HTTPS links opened from another browser arrive as web-browsing
    /// activities, not as document or custom-scheme URLs.
    func application(
        _: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler _: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let callback = userActivity.webpageURL
        else { return false }
        return callbackRouter.route(callback)
    }

    /// AppKit calls this whenever Curfew becomes the active app — including the
    /// user clicking back into a Curfew window after being away. Re-assert
    /// enforcement so a lockout that degraded while we were in the background
    /// recovers. No-ops when not locked.
    func applicationDidBecomeActive(_ notification: Notification) {
        model?.backgroundServiceManager.refreshStatus()
        model?.reassertEnforcementIfNeeded()
        // Re-poll Accessibility trust immediately on return, so granting access
        // in System Settings and switching back clears the warning banner at
        // once rather than waiting up to a second for the display clock's tick.
        model?.refreshAccessibilityTrust()
    }

    /// Closes the audit trail on a normal quit. A launch with no preceding
    /// `app.terminating` is how a reader — and the privileged daemon — tells
    /// a crash or a force-quit from an ordinary exit.
    ///
    /// Takes the presence camera down first. The process exiting would release
    /// the device anyway, but doing it explicitly closes the
    /// `presence.camera_started` record with a matching stop, so the log
    /// always bounds the window the camera was on.
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutDownPresence()
        model?.recordAuditAppTerminating()
    }
}
