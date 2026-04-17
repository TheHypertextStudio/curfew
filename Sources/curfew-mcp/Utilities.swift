import Foundation

/// Converts minutes-from-midnight to `"HH:MM"` format.
func minutesToHHMM(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

/// Returns the stable ASCII token for `phase` used in plain-text and JSON output.
func phaseName(_ phase: EnforcementPhase) -> String {
    switch phase {
    case .working: return "working"
    case .warning: return "warning"
    case .locked: return "locked"
    case .dayOff: return "day_off"
    }
}

extension Calendar {
    /// Monday-aligned week start for `date`. Matches the calculation used in
    /// `ActivityRollups.weeklyRollup` so budget counts agree with the app UI.
    func startOfWeek(for date: Date) -> Date {
        var components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = firstWeekday
        return self.date(from: components) ?? startOfDay(for: date)
    }
}
