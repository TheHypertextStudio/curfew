import CurfewKit
import Foundation
import OSLog

private let blockedLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "enforcement-ownership"
)

/// The other flavor enforcing this curfew while this process stands by, or `nil`
/// when this build owns enforcement (or isn't locked). Refreshed once per tick
/// by ``CurfewAppModel/reconcileEnforcementOwnership()``.
///
/// Kept here as a file-scoped value rather than a stored property on
/// ``CurfewAppModel`` because that type sits at its line-count cap, and there is
/// exactly one model per process — so process-global is equivalent to a single
/// instance's state.
private var standingByOwner: EnforcementOwner?

extension CurfewAppModel {
    /// Whether this build should actually engage blocking enforcement: it is in
    /// the locked phase *and* it holds the cross-flavor enforcement lock. Every
    /// blocking effect — the key shield, the lockout overlay, auto-shutdown —
    /// keys off this rather than `state.phase == .locked` directly, so that only
    /// one Curfew ever locks the user out at a time.
    var isEnforcingLockout: Bool {
        state.phase == .locked && standingByOwner == nil
    }

    /// The other flavor currently enforcing this curfew, while this build is
    /// locked but standing by. `nil` whenever this build is the enforcer (or
    /// isn't locked). Drives "another Curfew is enforcing" UI copy.
    var enforcementStandingBy: EnforcementOwner? {
        standingByOwner
    }

    /// Reconciles this build's claim on the single-enforcer lock. Called once
    /// per tick, before the blocking effects are applied.
    ///
    /// While locked it tries to take (or keep) ownership; production preempts a
    /// development build, and a development build stands aside for production. If
    /// another flavor owns the lock, ``enforcementStandingBy`` is set and the
    /// blocking effects are suppressed for this tick. When not locked it drops
    /// any ownership it held so the other flavor can take over immediately.
    func reconcileEnforcementOwnership() {
        // Skip under the unit-test host so ticking the model neither writes the
        // real lock file nor probes the machine's running apps. Tests exercise
        // `EnforcementOwnership` directly with injected collaborators.
        guard !RuntimeEnvironment.isUnitTestHost else { return }

        guard state.phase == .locked else {
            EnforcementOwnership.release()
            standingByOwner = nil
            return
        }

        switch EnforcementOwnership.acquire() {
        case .acquired:
            if let previous = standingByOwner {
                blockedLogger.info(
                    "took over enforcement; \(previous.displayName, privacy: .public) no longer owns it"
                )
                standingByOwner = nil
            }
        case .deniedHeldBy(let owner):
            if standingByOwner != owner {
                blockedLogger.info(
                    "standing by — \(owner.displayName, privacy: .public) already enforces this curfew"
                )
                standingByOwner = owner
            }
        }
    }
}
