import Foundation

/// Converts minutes-from-midnight to `"HH:MM"` format.
public func minutesToHHMM(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

/// Returns the stable ASCII token for `phase` used in plain-text and JSON output.
public func phaseName(_ phase: EnforcementPhase) -> String {
    switch phase {
    case .working: "working"
    case .warning: "warning"
    case .locked: "locked"
    case .dayOff: "day_off"
    }
}

public extension Calendar {
    /// Monday-aligned week start for `date`. Matches the calculation used in
    /// `ActivityRollups.weeklyRollup` so budget counts agree with the app UI.
    func startOfWeek(for date: Date) -> Date {
        var components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = firstWeekday
        return self.date(from: components) ?? startOfDay(for: date)
    }
}
