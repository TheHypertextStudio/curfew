import CurfewKit
import Foundation
import WidgetKit

// NOTE: This target must include (or symlink) the following files from Curfew/Core
// and Curfew/App so the widget compiles without importing the app module:
//   CurfewEnforcementEngine.swift, ScheduleModels.swift, DayRule.swift,
//   CurfewSettingsStore.swift, SharedPaths.swift, ExtensionBudgetTracker.swift,
//   SchedulePolicyEngine.swift, SchedulePreset.swift, WarningStage.swift,
//   EnforcementSnapshot.swift, ActivityEvent.swift, ActivityStore.swift,
//   ActivityRollups.swift.

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
    /// 15-minute entries so the ring stays fresh without burning
    /// background refresh budget.
    func getTimeline(in _: Context, completion: @escaping (Timeline<CurfewWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries: [CurfewWidgetEntry] = [current]

        // When we can see a lock time, enqueue one entry at each warning
        // threshold so the widget ring re-renders with the right color
        // and stage copy at each escalation.
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
        let engine = CurfewEnforcementEngine()
        let eval = engine.evaluate(
            at: date,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals,
            workedMinutesToday: 0
        )

        let rule = settings.schedule.rule(for: date)
        var phase = phaseToken(eval.phase)
        var minutesRemaining = eval.minutesRemaining
        var lockTime = rule.isDayOff ? nil : formatted(minutes: rule.lockMinutes)
        var unlockTime = rule.isDayOff ? nil : formatted(minutes: rule.unlockMinutes)

        // For the current entry, defer to the live enforcement snapshot the app
        // writes — it reflects active extensions/overrides, which the settings-
        // only estimate above cannot, so the widget agrees with Today and the
        // menu bar. The countdown is recomputed from the snapshot's
        // authoritative lockDate so the ring stays live between snapshot writes.
        // Future timeline entries are predictions and keep the settings estimate.
        if let live = currentLiveSnapshot(for: date) {
            phase = live.phase
            lockTime = live.lockDate.map(formattedClock) ?? lockTime
            unlockTime = live.unlockDate.map(formattedClock) ?? unlockTime
            if live.phase == "working" || live.phase == "warning",
               let lockDate = live.lockDate, lockDate > date {
                minutesRemaining = Int(lockDate.timeIntervalSince(date) / 60)
            } else {
                minutesRemaining = live.minutesRemaining
            }
        }

        let rollup = weeklyRollup(at: date)

        return CurfewWidgetEntry(
            date: date,
            phase: phase,
            minutesRemaining: minutesRemaining,
            lockTime: lockTime,
            unlockTime: unlockTime,
            warningStage: warningToken(eval.warningStage),
            trigger: eval.trigger.rawValue,
            workedMinutesToday: 0,
            weeklyStreakDays: rollup.streak,
            dailyBars: rollup.days.map { $0.hadLockout ? 1 : 0 }
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

    /// Formats a `Date` as the widget's `HH:mm` clock string, by converting to
    /// minutes-since-midnight and reusing ``formatted(minutes:)`` — the same
    /// formatter the settings-derived path uses — rather than a second
    /// parallel `String(format:)` call.
    private func formattedClock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return formatted(minutes: (components.hour ?? 0) * 60 + (components.minute ?? 0))
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

    /// Folds this week's activity events into a rollup. Empty rollup on
    /// any I/O failure so the widget never blocks on the SQLite open path.
    private func weeklyRollup(at date: Date) -> WeeklyActivityRollup {
        let calendar = Calendar.current
        let weekStart = mondayAlignedWeekStart(for: date, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        guard
            FileManager.default.fileExists(atPath: SharedPaths.activityDatabase.path),
            let store = try? ActivityStore(databaseURL: SharedPaths.activityDatabase),
            let events = try? store.events(in: weekStart ... weekEnd)
        else {
            return ActivityRollups.weeklyRollup(
                events: [],
                weekStart: weekStart,
                calendar: calendar
            )
        }
        return ActivityRollups.weeklyRollup(
            events: events,
            weekStart: weekStart,
            calendar: calendar
        )
    }

    // MARK: - Token helpers

    private func formatted(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

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

    /// Monday-aligned week start. Inlined here instead of pulling in
    /// CurfewKit so the widget target stays framework-free.
    private func mondayAlignedWeekStart(for date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear],
            from: date
        )
        components.weekday = calendar.firstWeekday
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Maps a `WarningStage` to the stable string token stored in the
    /// widget entry. Matches `WarningNotificationManager.token(for:)`.
    private func warningToken(_ stage: WarningStage) -> String {
        switch stage {
        case .none: "none"
        case .thirtyMinutes: "T-30"
        case .fifteenMinutes: "T-15"
        case .fiveMinutes: "T-5"
        case .twoMinutes: "T-2"
        case .oneMinute: "T-1"
        case .lockout: "lockout"
        }
    }
}
