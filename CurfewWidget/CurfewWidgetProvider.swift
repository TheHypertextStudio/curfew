import Foundation
import WidgetKit

// NOTE: This target must include (or symlink) the following files from Curfew/Core
// and Curfew/App so the widget compiles without importing the app module:
//   CurfewEnforcementEngine.swift, ScheduleModels.swift, DayRule.swift,
//   CurfewSettingsStore.swift, SharedPaths.swift, ExtensionBudgetTracker.swift,
//   SchedulePolicyEngine.swift, SchedulePreset.swift, WarningStage.swift,
//   EnforcementSnapshot.swift, ActivityEvent.swift, ActivityStore.swift,
//   ActivityRollups.swift.

struct CurfewWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> CurfewWidgetEntry {
        .placeholder
    }

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
        let defaults = UserDefaults(suiteName: "studio.hypertext.curfew") ?? .standard
        let settings = CurfewSettingsStore(defaults: defaults).load()
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
        let lockTime = rule.isDayOff ? nil : formatted(minutes: rule.lockMinutes)
        let unlockTime = rule.isDayOff ? nil : formatted(minutes: rule.unlockMinutes)

        let rollup = weeklyRollup(at: date)

        return CurfewWidgetEntry(
            date: date,
            phase: phaseToken(eval.phase),
            minutesRemaining: eval.minutesRemaining,
            lockTime: lockTime,
            unlockTime: unlockTime,
            warningStage: warningToken(eval.warningStage),
            trigger: eval.trigger.rawValue,
            workedMinutesToday: 0,
            weeklyStreakDays: rollup.streak,
            dailyBars: rollup.days.map { $0.hadLockout ? 1 : 0 }
        )
    }

    /// Resolves today's lock time so `getTimeline` can enqueue per-stage
    /// entries. Returns nil on day-off — the coarse 15-minute grid is
    /// enough when there's no warning to escalate.
    private func lookupLockDate(now: Date) -> Date? {
        let defaults = UserDefaults(suiteName: "studio.hypertext.curfew") ?? .standard
        let settings = CurfewSettingsStore(defaults: defaults).load()
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
