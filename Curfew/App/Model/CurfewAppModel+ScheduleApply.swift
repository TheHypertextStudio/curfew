import CurfewKit
import Foundation
import OSLog

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
    @discardableResult
    func queueScheduleUpdate(
        _ proposedSchedule: WeeklySchedule,
        requestedBy actor: AuditActor = .user,
        request: MCPPendingRequest? = nil
    ) -> Bool {
        var next = settings
        if !settings.hasCompletedInitialSetup || !automaticScheduleEnabled {
            next.schedule = proposedSchedule
            next.pendingScheduleChange = nil
        } else {
            let classification = policyEngine.classifyChange(
                from: settings.schedule, to: proposedSchedule
            )
            next.pendingScheduleChange = classification == .noChange ? nil : PendingScheduleChange(
                proposedSchedule: proposedSchedule,
                requestedAt: currentTime,
                effectiveAt: policyEngine.earliestEffectiveDate(
                    for: classification, requestedAt: currentTime
                ),
                classification: classification
            )
        }

        let cancelled = settings.pendingScheduleChange
        guard commitScheduleSettings(next, request: request) else { return false }
        if let pending = next.pendingScheduleChange {
            recordAuditScheduleRequested(
                proposed: proposedSchedule, classification: pending.classification,
                effectiveAt: pending.effectiveAt, actor: actor
            )
        } else if automaticScheduleEnabled, settings.hasCompletedInitialSetup, let cancelled {
            recordAuditScheduleCancelled(pending: cancelled, actor: actor)
        }
        refreshAfterScheduleEdit()
        return true
    }

    /// Publish the schedule only after the same durable write has recorded its request outcome.
    @discardableResult
    func commitScheduleSettings(_ next: CurfewSettings, request: MCPPendingRequest? = nil) -> Bool {
        if request != nil || next.schedule != settings.schedule ||
            next.pendingScheduleChange != settings.pendingScheduleChange {
            guard schedulePersistenceError == nil else { return false }
            do {
                try settingsStore.commitSchedule(
                    next, replacing: settings, request: request, at: currentTime
                )
            } catch {
                schedulePersistenceError = error.localizedDescription
                Logger(subsystem: "studio.hypertext.curfew", category: "schedule")
                    .error(
                        "Could not save the schedule: \(error.localizedDescription, privacy: .public)"
                    )
                return false
            }
        }
        if next != settings {
            settings = next
        }
        return true
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
        guard let pending = settings.pendingScheduleChange, now >= pending.effectiveAt else {
            return
        }
        if state.phase == .locked, pending.classification == .weaker {
            recordAuditScheduleDeferred(pending: pending, reason: "weaker_change_during_lockout")
            return
        }
        let previous = settings.schedule
        var next = settings
        next.schedule = pending.proposedSchedule
        next.pendingScheduleChange = nil
        guard commitScheduleSettings(next) else { return }
        recordAuditScheduleApplied(pending: pending, from: previous)
        flagScheduleChangeApplied()
    }
}
