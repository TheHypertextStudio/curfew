/// Pure policy deciding whether Curfew should re-assert its lockout enforcement
/// when the user returns to the Mac — on app activation or system wake.
///
/// A lockout can silently degrade while the Mac is asleep or another app is
/// front-most: macOS may have disabled the keyboard shield's event tap, and the
/// lockout overlay can lose its front-most z-order. When the user comes back, we
/// want to recover that degraded state rather than present a hollow lockout.
///
/// Kept free of any system dependency so it is trivially testable: callers feed
/// in the two facts that gate the decision (the current enforcement phase and
/// whether the keyboard shield's tap is live) and get back whether to re-assert.
/// The notification callback that drives this stays a thin translation layer.
enum EnforcementReassertion: Equatable {
    /// Re-assert enforcement: restart the keyboard shield and bring the lockout
    /// overlay back to the front.
    case reassert

    /// Do nothing — enforcement is not in a phase that needs re-assertion.
    case noop
}

/// Decides whether returning to the Mac should trigger an enforcement
/// re-assertion.
enum EnforcementReassertionPolicy {
    /// Resolves the re-assertion decision from the facts available when the app
    /// activates or the system wakes.
    ///
    /// Re-assertion is warranted whenever the model is in a ``EnforcementPhase``
    /// `.locked` phase — the keyboard shield must be running and the overlay must
    /// be front-most. A downed tap (`tapIsActive == false`) is the canonical
    /// degradation this recovers, but even a live tap warrants re-asserting the
    /// overlay's z-order after a wake, so the decision keys on the phase. Any
    /// non-locked phase is a no-op: there is no shield or overlay to restore.
    ///
    /// - Parameters:
    ///   - phase: The model's current enforcement phase.
    ///   - tapIsActive: Whether the keyboard shield's event tap is live. Only
    ///     informational for the locked case today; surfaced as a parameter so
    ///     the decision records the degradation it is recovering from and so
    ///     future policy (e.g. skip the restart when the tap is already healthy)
    ///     can refine the verdict without reshaping call sites.
    /// - Returns: ``EnforcementReassertion/reassert`` when locked, otherwise
    ///   ``EnforcementReassertion/noop``.
    static func decide(
        phase: EnforcementPhase,
        tapIsActive: Bool
    ) -> EnforcementReassertion {
        _ = tapIsActive
        return phase == .locked ? .reassert : .noop
    }
}
