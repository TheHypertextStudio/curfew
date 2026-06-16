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

/// Tracks whether `requestAccessibilityAccess()` has been called at least once
/// this session. File-scoped (following the pattern in
/// `CurfewAppModel+EnforcementOwnership.swift`) to avoid the model line-count cap.
private var hasShownAccessibilityPrompt = false

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
                tapExpectedActive: isEnforcingLockout,
                tapIsActive: tapIsActive
            )
        )
    }

    /// Re-polls Accessibility trust (and the folded enforcement-health verdict)
    /// without surfacing any prompt or opening System Settings.
    ///
    /// This is the read-only refresh the onboarding permissions gate drives on
    /// appear / on app activation / from its light timer: enforcement is not yet
    /// started during first run, so the per-tick poll is not running, yet the
    /// gate must still live-reflect a grant the user makes in System Settings.
    /// Because it only *reads* the seam (`AXIsProcessTrusted`, never the
    /// prompting `AXIsProcessTrustedWithOptions`), it is safe to call from any
    /// surface — including, via the injected fake, the unit-test host.
    func refreshAccessibilityTrust() {
        pollAndUpdateEnforcementHealth()
    }

    /// Surfaces the macOS Accessibility-trust prompt, then re-polls trust.
    ///
    /// `AXIsProcessTrustedWithOptions` with the prompt flag shows the system
    /// "Accessibility Access" dialog and registers Curfew in TCC. If the call
    /// returns `false` (not yet trusted), we also open the System Settings
    /// Accessibility pane directly — this handles the case where the system
    /// suppresses the dialog because a prior choice was already recorded, so
    /// the user can still reach the toggle without hunting for it manually.
    ///
    /// Recomputes ``enforcementHealth`` alongside trust so both published
    /// enforcement properties move together; otherwise the banner/badge would
    /// stay stale until the next tick.
    func requestAccessibilityAccess() {
        let trusted = accessibilityAuthorization.promptForTrust()
        // Only open Settings when TCC has already recorded a prior choice and is
        // suppressing the native dialog. On the very first call the system shows the
        // TCC prompt itself; opening Settings simultaneously races that dialog.
        if !trusted && hasShownAccessibilityPrompt {
            SystemAccessibilityAuthorization.openAccessibilitySettings()
        }
        hasShownAccessibilityPrompt = true
        pollAndUpdateEnforcementHealth()
    }
}
