import Foundation
import WidgetKit

/// Snapshot of enforcement state passed to the widget view.
///
/// Fields extended in v0.2 so the medium / large surfaces can show
/// work-time context and weekly retrospective at a glance. New fields
/// default to safe zeros so placeholder / snapshot paths don't have to
/// construct fake rollups.
struct CurfewWidgetEntry: TimelineEntry {
    /// Entry timestamp used by WidgetKit to pick the active entry.
    let date: Date
    /// Current enforcement phase: `working`, `warning`, `locked`, `day_off`.
    /// String (not the Swift enum) because `TimelineEntry` values must be
    /// `Decodable` across App <-> Widget process boundaries.
    let phase: String
    /// Whole minutes until the next phase transition. Decrements every
    /// timeline tick; always non-negative.
    let minutesRemaining: Int
    /// Today's lock time as `"HH:MM"`. `nil` on day-off and while locked
    /// (no further lock today to display).
    let lockTime: String?
    /// Today's unlock time as `"HH:MM"`. `nil` on day-off (no unlock
    /// applies).
    let unlockTime: String?
    /// Stable token for the current warning stage — `"none"`, `"T-30"`,
    /// `"T-15"`, `"T-5"`, `"T-2"`, `"T-1"`, `"lockout"`. Matches
    /// `WarningNotificationManager.token(for:)`.
    let warningStage: String

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

    /// Safe default entry used by `placeholder(in:)` and as fallback when
    /// the App Group container hasn't been populated yet (first launch).
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
