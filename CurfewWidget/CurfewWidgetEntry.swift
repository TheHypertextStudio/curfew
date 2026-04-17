import Foundation
import WidgetKit

/// Snapshot of enforcement state passed to the widget view.
///
/// Fields extended in v0.2 so the medium / large surfaces can show
/// work-time context and weekly retrospective at a glance. New fields
/// default to safe zeros so placeholder / snapshot paths don't have to
/// construct fake rollups.
struct CurfewWidgetEntry: TimelineEntry {
    let date: Date
    let phase: String // "working" | "warning" | "locked" | "day_off"
    let minutesRemaining: Int
    let lockTime: String? // "HH:MM" of today's lock, nil on day-off/locked
    let unlockTime: String? // "HH:MM" of today's unlock, nil on day-off
    let warningStage: String // "none" | "T-30" | "T-15" | …

    /// What clock drove the countdown — "time" or "hours". Matches the
    /// `trigger` field on `CurfewEvaluation`. Enables the widget to say
    /// "X min until curfew" vs. "X min of work hours left today".
    let trigger: String

    /// Active work minutes today across every synced device. 0 when no
    /// activity events exist yet today (first-tick-of-the-day case).
    let workedMinutesToday: Int

    /// Count of trailing consecutive days that ended in lockout, rendered
    /// as the "streak" pill on the large widget.
    let weeklyStreakDays: Int

    /// Per-day lockout counts for the current week, Monday-first, length 7.
    /// Feeds the large widget's mini bar chart.
    let dailyBars: [Int]

    static let placeholder = CurfewWidgetEntry(
        date: Date(),
        phase: "working",
        minutesRemaining: 120,
        lockTime: "22:00",
        unlockTime: "08:00",
        warningStage: "none",
        trigger: "time",
        workedMinutesToday: 0,
        weeklyStreakDays: 0,
        dailyBars: Array(repeating: 0, count: 7)
    )
}
