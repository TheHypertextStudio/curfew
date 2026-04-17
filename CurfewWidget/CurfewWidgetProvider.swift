import Foundation
import WidgetKit

// NOTE: This target must include (or symlink) the following files from Curfew/Core
// and Curfew/App so the widget compiles without importing the app module:
//   CurfewEnforcementEngine.swift, ScheduleModels.swift, CurfewSettingsStore.swift,
//   SharedPaths.swift, ExtensionBudgetTracker.swift, SchedulePolicyEngine.swift,
//   SchedulePreset.swift, WarningStage.swift, EnforcementSnapshot.swift

struct CurfewWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurfewWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CurfewWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurfewWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)

        // Refresh every 5 minutes — fine granularity for a countdown without
        // hammering the system. WidgetKit may coalesce refreshes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: now) ?? now
        let timeline = Timeline(entries: [current], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: - Private

    private func entry(at date: Date) -> CurfewWidgetEntry {
        let defaults = UserDefaults(suiteName: "studio.hypertext.curfew") ?? .standard
        let settings = CurfewSettingsStore(defaults: defaults).load()
        let engine = CurfewEnforcementEngine()
        let eval = engine.evaluate(
            at: date,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )

        let rule = settings.schedule.rule(for: date)
        let lockTime   = rule.isDayOff ? nil : formatted(minutes: rule.lockMinutes)
        let unlockTime = rule.isDayOff ? nil : formatted(minutes: rule.unlockMinutes)

        return CurfewWidgetEntry(
            date: date,
            phase: phaseToken(eval.phase),
            minutesRemaining: eval.minutesRemaining,
            lockTime: lockTime,
            unlockTime: unlockTime,
            warningStage: warningToken(eval.warningStage)
        )
    }

    private func formatted(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func phaseToken(_ phase: EnforcementPhase) -> String {
        switch phase {
        case .working: return "working"
        case .warning: return "warning"
        case .locked:  return "locked"
        case .dayOff:  return "day_off"
        }
    }

    private func warningToken(_ stage: WarningStage) -> String {
        switch stage {
        case .none:           return "none"
        case .thirtyMinutes:  return "T-30"
        case .fifteenMinutes: return "T-15"
        case .fiveMinutes:    return "T-5"
        case .twoMinutes:     return "T-2"
        case .oneMinute:      return "T-1"
        case .lockout:        return "lockout"
        }
    }
}
