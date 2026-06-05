import Foundation

/// Enforcement-health wiring for `CurfewAppModel`: the per-tick poll that
/// folds Accessibility trust and the keyboard shield's tap state into an
/// ``EnforcementHealth`` verdict, plus the user-facing request to grant trust.
///
/// Split into its own file so the tick loop in `CurfewAppModel+Lifecycle`
/// stays focused on enforcement evaluation, and so a reader asking "why does
/// the menu bar show a warning?" has one obvious place to look. The guarded
/// `private(set)` writes themselves live on the main class (Swift scopes a
/// `private(set)` setter to the declaring file); this extension drives them.
@MainActor
extension CurfewAppModel {
    /// Initial ``enforcementHealth`` seed, computed from the same facts the
    /// per-tick poll uses so the two published enforcement properties agree
    /// from t0 rather than `enforcementHealth` defaulting to ``/EnforcementHealth/active``
    /// while ``isAccessibilityTrusted`` may already say otherwise.
    ///
    /// `static` so the designated initialiser can call it before `super.init()`.
    /// The shield is never expected to run before the first tick, hence
    /// `tapExpectedActive: false`.
    ///
    /// - Parameters:
    ///   - isAccessibilityTrusted: Seeded Accessibility-trust state.
    ///   - tapIsEnabled: Whether the keyboard shield's tap is live at seed time.
    /// - Returns: The verdict to seed ``enforcementHealth`` with.
    static func seededEnforcementHealth(
        isAccessibilityTrusted: Bool,
        tapIsEnabled: Bool
    ) -> EnforcementHealth {
        EnforcementHealth.resolve(
            isAccessibilityTrusted: isAccessibilityTrusted,
            tapExpectedActive: false,
            tapIsActive: tapIsEnabled
        )
    }

    /// Re-polls Accessibility trust and recomputes ``enforcementHealth`` from
    /// the current phase and the live event-tap state. Called once per tick.
    ///
    /// The keyboard shield's tap is only expected to run during lockout, so an
    /// idle tap in any other phase — including the T-30/T-15/T-5 warning windows,
    /// where the user intentionally keeps full keyboard control — is still
    /// healthy. (`updateLockoutInterception` starts the tap only when the phase
    /// is `.locked` and stops it otherwise, so expecting it during warning would
    /// flag a false ``EnforcementHealth/degradedTapDown`` on every warning.) Both
    /// stored writes are guarded by their mutators so an unchanged verdict does
    /// not refresh every menu-bar surface each second.
    func pollAndUpdateEnforcementHealth() {
        let trusted = accessibilityAuthorization.isTrusted()
        setAccessibilityTrusted(trusted)
        // Use real tap liveness (`isEnabled`), not mere installation
        // (`isActive`): the OS can leave a tap installed yet disabled, which is
        // exactly the silent degradation the badge must surface. Tests inject
        // ``tapLivenessOverride`` because the live tap cannot run headlessly.
        let tapIsActive = tapLivenessOverride?() ?? lockoutKeyInterceptor.isEnabled
        setEnforcementHealth(
            EnforcementHealth.resolve(
                isAccessibilityTrusted: trusted,
                tapExpectedActive: state.phase == .locked,
                tapIsActive: tapIsActive
            )
        )
    }

    /// Surfaces the macOS Accessibility-trust prompt, opens the System Settings
    /// pane, then re-polls trust. Trust granted there only takes effect on
    /// relaunch, so the user typically stays untrusted until the next launch.
    ///
    /// Recomputes ``enforcementHealth`` alongside trust so both published
    /// enforcement properties move together; otherwise the banner/badge would
    /// stay stale until the next tick.
    func requestAccessibilityAccess() {
        accessibilityAuthorization.promptForTrust()
        SystemAccessibilityAuthorization.openAccessibilitySettings()
        pollAndUpdateEnforcementHealth()
    }
}
