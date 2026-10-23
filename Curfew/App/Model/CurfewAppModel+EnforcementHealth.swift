import AppKit
import Combine
import CurfewKit
import Foundation
import ServiceManagement

// Enforcement-health wiring for `CurfewAppModel`: the per-tick poll that
// folds Accessibility trust and the keyboard shield's tap state into an
// ``EnforcementHealth`` verdict, plus the user-facing request to grant trust.
//
// Split into its own file so the tick loop in `CurfewAppModel+Lifecycle`
// stays focused on enforcement evaluation, and so a reader asking "why does
// the menu bar show a warning?" has one obvious place to look. The guarded
// `private(set)` writes themselves live on the main class (Swift scopes a
// `private(set)` setter to the declaring file); this extension drives them.

@MainActor
extension CurfewAppModel {
    /// Refreshes Accessibility trust whenever Curfew becomes active again.
    /// This covers the common grant flow: the user leaves Curfew for System
    /// Settings, enables the existing Curfew entry, then returns while the
    /// enforcement timer is off.
    func subscribeToAccessibilityTrustChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshAccessibilityTrust()
            }
            .store(in: &cancellables)
    }

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
        tapIsEnabled: Bool,
        helperAvailability: PrivilegedEnforcementAvailability = .notRequired
    ) -> EnforcementHealth {
        EnforcementHealth.resolve(
            isAccessibilityTrusted: isAccessibilityTrusted,
            tapExpectedActive: false,
            tapIsActive: tapIsEnabled,
            helperAvailability: helperAvailability
        )
    }

    /// Resolves the helper feature gate before seeding launch-time health.
    static func resolvedSeededHealth(
        trusted: Bool,
        tapEnabled: Bool,
        flags: FeatureFlags,
        helper: PrivilegedHelperManager
    ) -> EnforcementHealth {
        let availability = flags.privilegedHelperEnabled
            ? helper.enforcementAvailability : .notRequired
        return seededEnforcementHealth(
            isAccessibilityTrusted: trusted,
            tapIsEnabled: tapEnabled,
            helperAvailability: availability
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
        retryUnavailableHelperIfDue()
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
                tapIsActive: tapIsActive,
                helperAvailability: featureFlags.privilegedHelperEnabled
                    ? privilegedHelperManager.enforcementAvailability
                    : .notRequired
            )
        )
    }

    /// A transient XPC interruption should not leave enforcement marked
    /// degraded until Settings is opened or the app is relaunched. Status RPC
    /// is read-only, single-flight, and capped at one attempt per 30 seconds.
    private func retryUnavailableHelperIfDue() {
        let helper = privilegedHelperManager
        guard featureFlags.privilegedHelperEnabled,
              !isDemoSession,
              helper.daemonStatus == .enabled,
              !helper.maintenancePaused,
              !helper.repairInProgress,
              !helper.installationInProgress,
              !helperStatusProbeInFlight,
              helper.connectionState == .unavailable || helper.connectionState == .stale
        else { return }
        if let lastHelperStatusProbeAt,
           currentTime.timeIntervalSince(lastHelperStatusProbeAt) >= 0,
           currentTime.timeIntervalSince(lastHelperStatusProbeAt) < 30 {
            return
        }

        lastHelperStatusProbeAt = currentTime
        helperStatusProbeInFlight = true
        Task { [weak self] in
            await helper.reconcileDaemonStatus()
            guard let self else { return }
            helperStatusProbeInFlight = false
            pollAndUpdateEnforcementHealth()
        }
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
    /// The prompt API registers Curfew in TCC but does not report whether macOS
    /// displayed a dialog. Missing live trust therefore also opens Settings.
    /// Existing trust instead permits an immediate shield-recovery attempt.
    ///
    /// Recomputes ``enforcementHealth`` alongside trust so both published
    /// enforcement properties move together; otherwise the banner/badge would
    /// stay stale until the next tick.
    func requestAccessibilityAccess() {
        accessibilityAuthorization.promptForTrust()
        pollAndUpdateEnforcementHealth()
        // AX reports current trust, not whether macOS displayed a dialog. An
        // explicit repair action must reach Settings even if TCC suppresses it.
        if !isAccessibilityTrusted {
            accessibilityAuthorization.openSettings()
        } else {
            reassertEnforcementIfNeeded()
        }
    }
}
