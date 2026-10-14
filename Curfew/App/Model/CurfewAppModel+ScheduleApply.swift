import CurfewKit
import Foundation

/// Schedule-mutation and pending-swap helpers for `CurfewAppModel`.
/// Split into its own extension so the tick-loop file stays inside the
/// lint length budget and the anti-bypass apply path is grep-able by
/// filename.
@MainActor
extension CurfewAppModel {
    /// Classifies `proposedSchedule` against the live one and persists
    /// the result as a `PendingScheduleChange` stamped with the earliest
    /// legal effective date. Also MCP's `curfew.set_schedule` entry
    /// point — shared path means shared anti-bypass semantics.
    func queueScheduleUpdate(
        _ proposedSchedule: WeeklySchedule,
        requestedBy actor: AuditActor = .user
    ) {
        // No automatic schedule is active before setup or in remote-only
        // mode, so editing stored rules cannot bypass a live weekly lockout.
        if !settings.hasCompletedInitialSetup || !automaticScheduleEnabled {
            settings.schedule = proposedSchedule
            settings.pendingScheduleChange = nil
            persistSettings()
            refreshAfterScheduleEdit()
            return
        }
        let classification = policyEngine.classifyChange(
            from: settings.schedule,
            to: proposedSchedule
        )
        if classification == .noChange {
            // Only worth a record when it cancels something. A no-op submit
            // fires on every stepper nudge in the schedule editor, and the
            // log must not fill with lines describing nothing happening.
            if let cancelled = settings.pendingScheduleChange {
                recordAuditScheduleCancelled(pending: cancelled, actor: actor)
            }
            settings.pendingScheduleChange = nil
            persistSettings()
            refreshAfterScheduleEdit()
            return
        }

        let effectiveDate = policyEngine.earliestEffectiveDate(
            for: classification,
            requestedAt: currentTime
        )
        recordAuditScheduleRequested(
            proposed: proposedSchedule,
            classification: classification,
            effectiveAt: effectiveDate,
            actor: actor
        )
        settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: proposedSchedule,
            requestedAt: currentTime,
            effectiveAt: effectiveDate,
            classification: classification
        )
        persistSettings()
        refreshAfterScheduleEdit()
    }

    private func refreshAfterScheduleEdit() {
        guard !isDemoSession else { return }
        if started {
            tick()
        } else {
            displayTick()
        }
    }

    /// Swaps in any `PendingScheduleChange` whose `effectiveAt` has
    /// arrived. Called once per tick before the engine runs.
    ///
    /// Anti-bypass: a `.weaker` change is held back when the device is
    /// currently in lockout. The 24-hour cooldown alone is insufficient —
    /// a user can submit the change Friday night and have it land mid-
    /// lockout on Saturday or Monday, releasing them early. Holding the
    /// swap until the next non-locked tick preserves the spirit of the
    /// cooldown ("can't escape this lockout via Settings").
    func applyPendingScheduleIfNeeded(now: Date) {
        guard let pending = settings.pendingScheduleChange else {
            return
        }
        guard now >= pending.effectiveAt else {
            return
        }
        if state.phase == .locked, pending.classification == .weaker {
            recordAuditScheduleDeferred(pending: pending, reason: "weaker_change_during_lockout")
            return
        }
        recordAuditScheduleApplied(pending: pending)
        settings.schedule = pending.proposedSchedule
        settings.pendingScheduleChange = nil
        persistSettings()
        flagScheduleChangeApplied()
    }
}
