import CurfewKit
import Foundation

/// In-app routes that would end or sidestep a lockout — uninstall and quit —
/// stay closed while the curfew holds.
@MainActor
extension CurfewAppModel {
    static let uninstallBlockedMessage = "Uninstall is available once curfew lifts."

    /// Uninstall removes the overlay and the background services, so it waits
    /// for both the locked phase and any durable deadline (which also outlasts
    /// an override) to end.
    var uninstallIsBlockedByCurfew: Bool {
        if state.phase == .locked {
            return true
        }
        guard let record = lockoutDeadlineStore.load() else { return false }
        return currentTime < record.scheduledUnlockAt
    }

    /// Whether an ordinary quit may proceed. Logout, restart, and shutdown are
    /// allowed separately by the app delegate.
    var allowsQuit: Bool {
        !isEnforcingLockout
    }
}
