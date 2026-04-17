import SwiftUI

/// "This Week" retrospective surface — a compact summary of the user's
/// current-week curfew behaviour.
///
/// Pulls its data from ``CurfewAppModel/thisWeekRollup()``, which folds
/// the `ActivityStore` events into a ``WeeklyActivityRollup``. `@Published
/// var currentTime` triggers body re-evaluation every tick, so this view
/// re-runs the (indexed, small-range) SQLite query once per second while
/// visible. Acceptable at v0.1 traffic (<100 events per week), but a
/// future optimisation is to memoise by week-start and invalidate only on
/// recorder writes.
///
/// Intentionally lightweight for v0.1: four headline numbers, seven
/// per-day cells. Pattern insights, CSV export, and device attribution
/// are tracked in §12 of the todo list and slot in here later.
struct ThisWeekView: View {
    /// Shared app model. The view reads `thisWeekRollup()` on every body
    /// evaluation rather than caching, because the rollup depends on
    /// `currentTime` (which advances every tick).
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        let rollup = model.thisWeekRollup()

        CurfewPanel {
            CurfewSectionTitle(
                title: "This Week",
                subtitle: "A glance at how your curfew has held up."
            )

            headlineMetrics(rollup: rollup)
            Divider()
            dayGrid(rollup: rollup)
        }
    }

    /// Four-up tile row: streak, days with lockout, extensions used,
    /// overrides used. Lives at the top so it's visible without scrolling.
    private func headlineMetrics(rollup: WeeklyActivityRollup) -> some View {
        HStack(alignment: .top, spacing: 16) {
            metricTile(
                headline: "\(rollup.streak)",
                supporting: rollup.streak == 1 ? "day streak" : "days streak"
            )
            metricTile(
                headline: "\(rollup.daysWithLockout)/7",
                supporting: "days held"
            )
            metricTile(
                headline: "\(rollup.totalExtensionCount)",
                supporting: rollup.totalExtensionMinutes > 0
                    ? "extensions (\(rollup.totalExtensionMinutes)m)"
                    : "extensions"
            )
            metricTile(
                headline: "\(rollup.totalOverrideCount)",
                supporting: rollup.totalOverrideMinutes > 0
                    ? "overrides (\(rollup.totalOverrideMinutes)m)"
                    : "overrides"
            )
        }
    }

    /// Seven equal-width columns representing each day of the week. A
    /// filled dot indicates a day that ended in lockout; the weekday
    /// label below sits underneath.
    private func dayGrid(rollup: WeeklyActivityRollup) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(rollup.days.enumerated()), id: \.offset) { _, day in
                dayCell(day: day)
            }
        }
    }

    /// Static two-letter weekday formatter shared across cells. A fresh
    /// `DateFormatter` allocation is non-trivial (Foundation lock +
    /// ICU setup), so we cache one instance rather than rebuilding 7
    /// per body evaluation.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "EE"
        return formatter
    }()

    private func metricTile(headline: String, supporting: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(CurfewTypography.display(28))
                .foregroundStyle(CurfewTheme.ink)
            Text(supporting)
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayCell(day: DailyActivityRollup) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(day.hadLockout ? CurfewTheme.accent : CurfewTheme.surfaceMuted)
                .frame(width: 14, height: 14)
            Text(weekdayLabel(for: day.day))
                .font(CurfewTypography.label(11))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
        .frame(maxWidth: .infinity)
    }

    /// Two-letter weekday label (Mo / Tu / …) in the user's locale.
    /// Uses the veryShort symbols for compactness — the full names don't
    /// fit in the seven-column grid at typical window widths.
    private func weekdayLabel(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }
}
