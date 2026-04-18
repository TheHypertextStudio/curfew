import Foundation

/// Warning-stage dedupe across devices. Carved out of `+Lifecycle.swift`
/// so the tick body stays inside the lint budget and the publish / record
/// helpers live next to each other.
///
/// Contract:
///   - `warningStagesFiredToday` is the set of tokens ("T-30", "T-15", …)
///     that have fired somewhere for this iCloud account today. Seeded on
///     sync start from the shared `LockoutState` CKRecord; extended each
///     time this Mac's notification manager fires a new stage.
///   - Day rollover resets the set (done in `+Lifecycle`'s `tick()`).
///   - `WarningNotificationManager.update` receives the set and suppresses
///     any stage whose token is already present — a Mac joining
///     mid-escalation stays silent on alarms another Mac already raised.
@MainActor
extension CurfewAppModel {
    /// After the notification manager has had a chance to fire, records
    /// the current stage in `warningStagesFiredToday` if it's not already
    /// present, and pushes the updated set to CloudKit so other devices
    /// learn about it. Runs every tick; the stage-token compare makes it
    /// a no-op outside transitions.
    func recordWarningStageFiringIfNeeded() {
        let stageToken = WarningNotificationManager.token(for: state.warningStage)
        guard stageToken != "none",
              !warningStagesFiredToday.contains(stageToken)
        else {
            return
        }
        warningStagesFiredToday.insert(stageToken)
        cloudKitSyncEngine.pushLockoutState(
            phase: phaseTokenString(state.phase),
            warningPhaseStarted: state.phase == .warning ? currentTime : nil,
            lockedAt: state.phase == .locked ? state.lockDate : nil,
            unlocksAt: state.phase == .locked ? state.unlockDate : nil,
            warningStagesFired: warningStagesFiredToday
        )
    }

    /// Pushes the current lockout snapshot to CloudKit on phase transitions
    /// so devices joining mid-warning see the right baseline. `warning-
    /// PhaseStarted` is stamped on the first working→warning step and
    /// cleared on any exit from the warning phase.
    func publishLockoutStateIfSyncActive(previous: EnforcementPhase) {
        let warningStarted: Date? = state.phase == .warning && previous != .warning
            ? currentTime
            : nil
        cloudKitSyncEngine.pushLockoutState(
            phase: phaseTokenString(state.phase),
            warningPhaseStarted: warningStarted,
            lockedAt: state.phase == .locked ? state.lockDate : nil,
            unlocksAt: state.phase == .locked ? state.unlockDate : nil,
            warningStagesFired: warningStagesFiredToday
        )
    }

    /// Token form of an `EnforcementPhase` for the `LockoutState` record.
    private func phaseTokenString(_ phase: EnforcementPhase) -> String {
        switch phase {
        case .working: "working"
        case .warning: "warning"
        case .locked: "locked"
        case .dayOff: "day_off"
        }
    }
}
