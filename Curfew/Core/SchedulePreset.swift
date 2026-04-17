import Foundation

/// One of a small set of ready-made weekly schedules the user can apply in
/// one click, instead of building a schedule from scratch.
///
/// The raw string value is the display label shown in the Settings preset
/// picker. Kept in `Curfew/Core/` rather than `Curfew/UI/` because the
/// domain concept ("named schedule template") is semantic, not presentational
/// — the CLI and MCP server also want to say "apply nine-to-five" without
/// depending on SwiftUI.
///
/// Preset → concrete `WeeklySchedule` mappings live on `WeeklySchedule`
/// itself (`.standardNineToFive`, `.startupHours`, `.halfDay`). This enum
/// only identifies which preset was chosen.
enum SchedulePreset: String, CaseIterable, Identifiable {
    /// 9am–5pm weekdays, weekends off.
    case nineToFive = "9-to-5"

    /// 8am–8pm weekdays, weekends off.
    case startupHours = "Startup Hours"

    /// 8am–1pm weekdays (short day), weekends off.
    case halfDay = "Half Day"

    var id: String {
        rawValue
    }
}
