import Foundation
import OSLog

/// Respawn-guard wiring for the user-space ``PersistentLockdown``
/// LaunchAgent. Split into its own extension so the tick-loop file
/// stays inside the lint-enforced length budget; these helpers are
/// called from `CurfewAppModel.start()` (install) and from
/// `propagatePhaseTransition` (arm/disarm).
@MainActor
extension CurfewAppModel {
    /// Arms the user-space LaunchAgent on lockout entry; disarms on exit.
    /// Failures are logged and swallowed — bypass deterrence is best-
    /// effort, never a crash surface. In Debug `respawnGuard` is the
    /// `NoOpRespawnGuard` and these calls have no effect.
    func toggleRespawnGuardIfPhaseChanged(previousPhase: EnforcementPhase) {
        guard previousPhase != state.phase else { return }
        let logger = Logger(subsystem: "studio.hypertext.curfew", category: "respawn-guard")
        if state.phase == .locked {
            do {
                try respawnGuard.arm()
            } catch {
                logger.error(
                    "respawn guard arm failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        } else if previousPhase == .locked {
            do {
                try respawnGuard.disarm()
            } catch {
                logger.error(
                    "respawn guard disarm failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Calls `respawnGuard.install()` once per `start()`. Idempotent at
    /// the LaunchAgent level — `launchctl load` of an already-loaded
    /// agent is a no-op error we swallow. Debug builds inject
    /// `NoOpRespawnGuard` so this is a no-op under Xcode.
    func installRespawnGuardIfNeeded() {
        do {
            try respawnGuard.install()
        } catch {
            Logger(subsystem: "studio.hypertext.curfew", category: "respawn-guard")
                .error(
                    "respawn guard install failed: \(error.localizedDescription, privacy: .public)"
                )
        }
    }
}
