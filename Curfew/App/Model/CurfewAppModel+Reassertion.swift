import AppKit
import Foundation

/// Enforcement re-assertion wiring for `CurfewAppModel`: recovers a degraded
/// lockout when the user returns to the Mac, on app activation and on system
/// wake.
///
/// A lockout can silently degrade while the Mac sleeps or another app is
/// front-most — macOS may disable the keyboard shield's event tap, and the
/// lockout overlay can lose its front-most z-order. The AppDelegate forwards
/// `applicationDidBecomeActive` here, and the model itself observes
/// `NSWorkspace.didWakeNotification` / `screensDidWakeNotification` (registered
/// in `start()`), so a returning user lands on a fully-restored lockout rather
/// than a hollow one.
///
/// Split into its own file so the decision (a pure
/// ``EnforcementReassertionPolicy``) and its thin system-side effects live in
/// one place, keeping the tick loop and the main class body focused.
@MainActor
extension CurfewAppModel {
    /// Re-polls enforcement health, then re-asserts the lockout shield and
    /// overlay when the model is in a locked phase. Returns the decision so
    /// callers (and tests) can see whether a re-assertion happened.
    ///
    /// Always re-polls health first so a permission revoked while the Mac was
    /// away surfaces the instant the user returns — even when no re-assertion is
    /// warranted. The re-assertion side effects themselves are already
    /// test-host-guarded: ``LockoutKeyInterceptor/start()`` no-ops under the unit
    /// test host (it would otherwise raise the Accessibility prompt), and the
    /// overlay re-order touches only already-created windows.
    ///
    /// - Returns: ``EnforcementReassertion/reassert`` when enforcement was
    ///   re-asserted, otherwise ``EnforcementReassertion/noop``.
    @discardableResult
    func reassertEnforcementIfNeeded() -> EnforcementReassertion {
        pollAndUpdateEnforcementHealth()

        let tapIsActive = tapLivenessOverride?() ?? lockoutKeyInterceptor.isEnabled
        let decision = EnforcementReassertionPolicy.decide(
            phase: state.phase,
            tapIsActive: tapIsActive
        )

        guard decision == .reassert else { return .noop }

        // Restart the keyboard shield (idempotent; no-ops if the tap is already
        // live, and skipped entirely under the unit-test host) and bring the
        // lockout overlay back to the front of the z-order.
        lockoutKeyInterceptor.start()
        overlayCoordinator.reassertLockoutFrontmost()
        return .reassert
    }

    /// Registers the system-wake observers that drive re-assertion. Called once
    /// from `start()`. Guarded by ``RuntimeEnvironment/isUnitTestHost`` so a
    /// re-signed test build never registers live `NSWorkspace` observers (which
    /// would fire during unrelated tests and reach into AppKit). App activation
    /// is wired separately through the AppDelegate.
    func startEnforcementReassertionObservers() {
        guard !RuntimeEnvironment.isUnitTestHost else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ] {
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    _ = self?.reassertEnforcementIfNeeded()
                }
            }
        }
    }
}
