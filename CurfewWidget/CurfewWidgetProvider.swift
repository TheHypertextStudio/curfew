import CurfewKit
import Foundation
import WidgetKit

/// WidgetKit `TimelineProvider` that reads from the shared App Group
/// container, computes an enforcement snapshot, and emits entries at
/// each warning threshold plus coarse 15-minute grid entries.
struct CurfewWidgetProvider: TimelineProvider {
    /// Returns the safe placeholder entry rendered in the widget
    /// gallery and during data-loading transitions.
    func placeholder(in _: Context) -> CurfewWidgetEntry {
        .placeholder
    }

    /// Single-shot snapshot for the widget picker preview. Reads live
    /// settings so the gallery mirrors the user's real schedule.
    func getSnapshot(in _: Context, completion: @escaping (CurfewWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    /// Produces a timeline with one entry per warning stage inside the
    /// next hour (T-30, T-15, T-5, T-2, T-1, T-0) so the widget updates
    /// at the exact moments the user cares about — not at arbitrary
    /// 5-minute grid cells. Outside the warning window we fall back to
    /// 15-minute entries so the countdown stays fresh without burning
    /// background refresh budget.
    func getTimeline(in _: Context, completion: @escaping (Timeline<CurfewWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries: [CurfewWidgetEntry] = [current]

        // When we can see a lock time, enqueue one entry at each warning
        // threshold so the countdown is exact at each warning.
        if let lockDate = lookupLockDate(now: now), lockDate > now {
            for minutesBeforeLock in [30, 15, 5, 2, 1, 0] {
                let stageDate = lockDate.addingTimeInterval(
                    -TimeInterval(minutesBeforeLock * 60)
                )
                guard stageDate > now else { continue }
                entries.append(entry(at: stageDate))
            }
        }

        // Outside the warning window we still want occasional refreshes.
        // WidgetKit coalesces budget-heavy timelines; 15-minute entries
        // for the next 2 hours is a cheap compromise.
        let coarseStep = 15
        for minutesFromNow in stride(from: coarseStep, through: 120, by: coarseStep) {
            let date = Calendar.current.date(
                byAdding: .minute,
                value: minutesFromNow,
                to: now
            ) ?? now
            if !entries.contains(where: { abs($0.date.timeIntervalSince(date)) < 30 }) {
                entries.append(entry(at: date))
            }
        }

        let sorted = entries.sorted { $0.date < $1.date }
        let policy: TimelineReloadPolicy
        if let last = sorted.last {
            let nextReload = last.date.addingTimeInterval(15 * 60)
            policy = .after(nextReload)
        } else {
            policy = .after(now.addingTimeInterval(15 * 60))
        }
        completion(Timeline(entries: sorted, policy: policy))
    }

    // MARK: - Entry construction

    private func entry(at date: Date) -> CurfewWidgetEntry {
        let settings = WidgetSharedStateStore().loadSettings()
        let eval = CurfewEnforcementEngine().evaluate(
            at: date,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals,
            workedMinutesToday: 0
        )

        var phase = phaseToken(eval.phase)
        var minutesRemaining = eval.minutesRemaining
        var lockDate = eval.lockDate
        var unlockDate = eval.unlockDate

        // For the current entry, defer to the live snapshot the app writes: it
        // reflects more time and overrides, which the settings-only estimate
        // cannot, so the widget agrees with Today and the menu bar. Future
        // timeline entries are predictions and keep the settings estimate.
        if let live = currentLiveSnapshot(for: date) {
            phase = live.phase
            lockDate = live.lockDate ?? lockDate
            unlockDate = live.unlockDate ?? unlockDate
            if live.phase == "working" || live.phase == "warning",
               let liveLock = live.lockDate, liveLock > date {
                minutesRemaining = Int(liveLock.timeIntervalSince(date) / 60)
            } else {
                minutesRemaining = live.minutesRemaining
            }
        }

        return CurfewWidgetEntry(
            date: date,
            phase: phase,
            minutesRemaining: minutesRemaining == .max ? 0 : max(0, minutesRemaining),
            lockDate: lockDate,
            unlockDate: unlockDate
        )
    }

    /// The live enforcement snapshot, but only for the current entry (≈ now) and
    /// only when recent enough to trust over the schedule-derived estimate — a
    /// snapshot from an app that's been quit for a while shouldn't override a
    /// fresh prediction. Future timeline entries always return nil here.
    private func currentLiveSnapshot(for date: Date) -> WidgetEnforcementSnapshot? {
        guard abs(date.timeIntervalSince(Date())) < 60 else { return nil }
        guard let snapshot = WidgetSharedStateStore().loadEnforcement() else { return nil }
        guard Date().timeIntervalSince(snapshot.updatedAt) < 90 * 60 else { return nil }
        return snapshot
    }

    /// Resolves today's lock time so `getTimeline` can enqueue per-stage
    /// entries. Returns nil on day-off — the coarse 15-minute grid is
    /// enough when there's no warning to escalate.
    private func lookupLockDate(now: Date) -> Date? {
        let settings = WidgetSharedStateStore().loadSettings()
        guard
            let window = settings.schedule.scheduleWindow(
                for: now,
                extensionMinutesGrantedToday: 0,
                calendar: .current
            )
        else {
            return nil
        }
        return window.lockDate
    }

    // MARK: - Token helpers

    /// Maps an `EnforcementPhase` to the lowercase string token stored
    /// in the widget entry. Kept symmetrical with the view's decoder.
    private func phaseToken(_ phase: EnforcementPhase) -> String {
        switch phase {
        case .working: "working"
        case .warning: "warning"
        case .locked: "locked"
        case .dayOff: "day_off"
        }
    }
}
