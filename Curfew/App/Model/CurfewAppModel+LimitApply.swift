import CurfewKit
import Foundation

/// Weekly limit edits and their pending-raise swap. The limit-side twin of
/// `CurfewAppModel+ScheduleApply.swift`: raising a limit waits the same
/// cooldown a looser schedule waits, computed by the same
/// `SchedulePolicyEngine`, and lowering one applies at once.
///
/// The four limit fields on `settings` always hold the value in force, so
/// every reader (Today's more time, the lock's override, MCP, the CLI, the
/// widget, budget trackers) sees a raise only once it applies. Settings is the
/// only surface that reads ``requestedLimit(_:)``.
@MainActor
extension CurfewAppModel {
    var limitPolicy: WeeklyLimitPolicy {
        WeeklyLimitPolicy(engine: policyEngine)
    }

    /// Applies a lower value now, or queues a higher one. The only way the
    /// app changes a weekly limit.
    func requestLimit(_ limit: WeeklyLimit, value: Int) {
        let next = limitPolicy.request(limit, value: value, in: settings, at: currentTime)
        guard next != settings else { return }
        settings = next
    }

    /// Withdraws a waiting raise, keeping the value in force.
    func cancelPendingLimit(_ limit: WeeklyLimit) {
        requestLimit(limit, value: settings[limit])
    }

    /// What Settings shows the stepper at: the waiting raise, or the value in
    /// force when nothing is waiting.
    func requestedLimit(_ limit: WeeklyLimit) -> Int {
        settings.requestedLimit(limit)
    }

    /// Swaps in waiting raises whose time has arrived. Called once per tick
    /// after the engine has evaluated this tick's phase, so a clock that jumps
    /// straight into tonight's lock is seen as locked and the raise is held,
    /// just as a looser schedule is held during lockout.
    func applyPendingLimitsIfNeeded(now: Date) {
        guard !settings.pendingLimitChanges.isEmpty else { return }
        let result = limitPolicy.applyDue(in: settings, at: now, isLocked: state.phase == .locked)
        guard result.settings != settings else { return }
        settings = result.settings
    }

    /// The line under a limit's label while a raise waits, or `nil`.
    func pendingLimitDescription(for limit: WeeklyLimit) -> String? {
        guard let pending = settings.pendingLimitChange(for: limit) else { return nil }
        let raised = LimitSurfaceCopy.value(pending.value, of: limit)
        let standing = LimitSurfaceCopy.value(settings[limit], of: limit)
        guard pending.effectiveAt > currentTime else {
            return LimitSurfaceCopy.waitingForUnlock(raised, standing: standing)
        }
        return LimitSurfaceCopy.waiting(
            raised,
            day: pending.effectiveAt.formatted(.dateTime.month(.abbreviated).day()),
            time: pending.effectiveAt.formatted(date: .omitted, time: .shortened),
            standing: standing
        )
    }
}
