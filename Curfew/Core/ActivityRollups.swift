import Foundation

/// Daily summary row. One instance per calendar day within the observed
/// week. Produced by ``ActivityRollups/weeklyRollup(events:weekStart:calendar:)``.
///
/// Values are zeroed rather than `Optional` so view code can render
/// "0 extensions" without a nil-coalesce at every call site. A day with
/// zero activity still appears in the weekly output so the streak and
/// day-of-week grid stay contiguous.
struct DailyActivityRollup: Equatable {
    /// Start-of-day moment this rollup bucket is keyed on. Stored as a
    /// `Date` (not a `DateComponents`) so timeline rendering can compare
    /// directly against other absolute timestamps.
    let day: Date

    /// Number of extensions the user claimed this day.
    let extensionCount: Int

    /// Total minutes granted by those extensions combined.
    let extensionMinutes: Int

    /// Number of overrides granted via the "Convince Me" flow.
    let overrideCount: Int

    /// Total minutes granted by those overrides combined.
    let overrideMinutes: Int

    /// Whether the user hit lockout today. False means either the day was
    /// off, the app wasn't running, or the user ended the working window
    /// before curfew fired.
    let hadLockout: Bool
}

/// Weekly summary produced by folding a `[ActivityEvent]` slice into per-
/// day rollups.
///
/// `days` is always seven entries long covering `[weekStart,
/// weekStart + 7 days)`; missing days carry zero rollups so downstream
/// callers can iterate the array without gap handling. Totals are
/// pre-computed so the UI doesn't have to re-fold in `body`.
struct WeeklyActivityRollup: Equatable {
    /// Per-day rollups in chronological order, length always 7.
    let days: [DailyActivityRollup]

    /// Sum of ``DailyActivityRollup/extensionCount`` across the week.
    let totalExtensionCount: Int

    /// Sum of ``DailyActivityRollup/extensionMinutes``.
    let totalExtensionMinutes: Int

    /// Sum of ``DailyActivityRollup/overrideCount``.
    let totalOverrideCount: Int

    /// Sum of ``DailyActivityRollup/overrideMinutes``.
    let totalOverrideMinutes: Int

    /// Number of days this week that ended in a lockout — a proxy for
    /// "how consistently the commitment was kept" until §11 work-hour
    /// accounting lands.
    let daysWithLockout: Int

    /// Trailing-end consecutive-day lockout count. If the most recent
    /// day in `days` had a lockout and so did the day before, the streak
    /// is 2; a gap resets to 0. Calculated from the latest lockout day
    /// (not necessarily the last array entry) so a mid-week view shows a
    /// meaningful streak on Wednesday.
    let streak: Int
}

/// Namespace for the pure-function rollup builder. Kept as an `enum` with
/// static methods (rather than injecting into `ActivityStore`) so tests
/// can exercise the aggregation on hand-built event arrays without
/// opening a database.
enum ActivityRollups {
    /// Width of the rollup window in days.
    private static let daysPerWeek = 7

    /// Folds an event slice into a ``WeeklyActivityRollup``.
    ///
    /// - Parameters:
    ///   - events: events to aggregate. May include entries outside the
    ///     target week; they are filtered out here.
    ///   - weekStart: the calendar day the week begins on. Typically the
    ///     `firstWeekday` anchored to today's week.
    ///   - calendar: calendar used for day bucketing + arithmetic. Tests
    ///     pin a UTC calendar to avoid DST and timezone drift.
    static func weeklyRollup(
        events: [ActivityEvent],
        weekStart: Date,
        calendar: Calendar
    ) -> WeeklyActivityRollup {
        let startOfWeek = calendar.startOfDay(for: weekStart)
        let dayStarts = (0 ..< daysPerWeek).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
        let endOfWeek = calendar.date(
            byAdding: .day,
            value: daysPerWeek,
            to: startOfWeek
        ) ?? startOfWeek

        // Bucket events by start-of-day. The filter also drops anything
        // outside `[startOfWeek, endOfWeek)` so callers don't have to
        // pre-slice.
        var buckets: [Date: DailyAccumulator] = [:]
        for event in events where event.timestamp >= startOfWeek && event.timestamp < endOfWeek {
            let day = calendar.startOfDay(for: event.timestamp)
            buckets[day, default: DailyAccumulator()].ingest(event)
        }

        let dailyRollups = dayStarts.map { day in
            (buckets[day] ?? DailyAccumulator()).rollup(for: day)
        }

        let totalExtensionCount = dailyRollups.reduce(0) { $0 + $1.extensionCount }
        let totalExtensionMinutes = dailyRollups.reduce(0) { $0 + $1.extensionMinutes }
        let totalOverrideCount = dailyRollups.reduce(0) { $0 + $1.overrideCount }
        let totalOverrideMinutes = dailyRollups.reduce(0) { $0 + $1.overrideMinutes }
        let daysWithLockout = dailyRollups.reduce(0) { $0 + ($1.hadLockout ? 1 : 0) }
        let streak = trailingStreak(in: dailyRollups)

        return WeeklyActivityRollup(
            days: dailyRollups,
            totalExtensionCount: totalExtensionCount,
            totalExtensionMinutes: totalExtensionMinutes,
            totalOverrideCount: totalOverrideCount,
            totalOverrideMinutes: totalOverrideMinutes,
            daysWithLockout: daysWithLockout,
            streak: streak
        )
    }

    /// Walks back from the latest lockout day and counts consecutive days
    /// with `hadLockout == true`. Days with no lockout break the streak.
    ///
    /// The scan anchors on the *latest* lockout day rather than today-
    /// relative so mid-week views ("it's Wednesday; Mon + Tue both hit
    /// lockout") still report a streak of 2 instead of requiring today's
    /// lockout to have already fired.
    private static func trailingStreak(
        in dailyRollups: [DailyActivityRollup]
    ) -> Int {
        guard let lastLockoutIndex = dailyRollups.lastIndex(where: { $0.hadLockout }) else {
            return 0
        }
        var streak = 0
        var index = lastLockoutIndex
        while index >= 0, dailyRollups[index].hadLockout {
            streak += 1
            index -= 1
        }
        return streak
    }
}

/// Per-day mutable accumulator used during the rollup fold. Private to
/// this file; the public surface is the immutable ``DailyActivityRollup``.
private struct DailyAccumulator {
    private var extensionCount = 0
    private var extensionMinutes = 0
    private var overrideCount = 0
    private var overrideMinutes = 0
    private var hadLockout = false

    mutating func ingest(_ event: ActivityEvent) {
        switch event.kind {
        case .extensionGranted:
            extensionCount += 1
            extensionMinutes += event.minutesValue ?? 0
        case .overrideGranted:
            overrideCount += 1
            overrideMinutes += event.minutesValue ?? 0
        case .lockoutStarted:
            hadLockout = true
        case .sessionStarted, .sessionEnded, .lockoutEnded,
             .warningEscalated, .dayOff:
            break
        }
    }

    func rollup(for day: Date) -> DailyActivityRollup {
        DailyActivityRollup(
            day: day,
            extensionCount: extensionCount,
            extensionMinutes: extensionMinutes,
            overrideCount: overrideCount,
            overrideMinutes: overrideMinutes,
            hadLockout: hadLockout
        )
    }
}
