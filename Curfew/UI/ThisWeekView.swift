import AppKit
import Charts
import CurfewKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(CurfewAppModel.self) private var model

    /// Weekly rollup panel — lockout count, extensions/overrides used,
    /// per-day bar chart, and streak pill.
    var body: some View {
        let rollup = model.thisWeekRollup()

        CurfewPanel {
            HStack {
                CurfewSectionTitle(
                    title: "This Week",
                    subtitle: "A glance at how your curfew has held up."
                )
                Spacer()
                Button("Export CSV") {
                    exportThisWeek()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }

            headlineMetrics(rollup: rollup)
            Divider()
            weeklyActivity(rollup: rollup)

            let devices = model.overridesByDeviceThisWeek()
            if devices.count >= 2 || (devices.count == 1 && devices.values.first ?? 0 >= 2) {
                Divider()
                deviceBreakdown(devices: devices)
            }

            if model.featureFlags.calendarEnabled, model.licenseGate.isPlusUnlocked,
               !model.calendarMonitor.todayEvents.isEmpty {
                Divider()
                calendarSection
            }
        }
    }

    /// Per-device override counts. Hidden when there's only one device
    /// and fewer than two overrides — that's the degenerate case where
    /// the headline number already tells the whole story.
    private func deviceBreakdown(devices: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Overrides by device")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)

            ForEach(devices.sorted { $0.value > $1.value }, id: \.key) { name, count in
                HStack {
                    Text(name)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.ink)
                    Spacer()
                    Text("\(count)")
                        .font(CurfewTypography.bodyEmphasis(13))
                        .foregroundStyle(CurfewTheme.accent)
                        .monospacedDigit()
                }
            }
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

    /// Weekly activity section. Shows the per-day Swift Charts bar chart
    /// when there's something to plot, and a native ``ContentUnavailableView``
    /// for an untouched week so the panel never renders an empty axis.
    @ViewBuilder
    private func weeklyActivity(rollup: WeeklyActivityRollup) -> some View {
        if hasActivity(rollup) {
            activityChart(rollup: rollup)
        } else {
            emptyState
        }
    }

    /// Whether the week recorded any lockout, extension, or override. Drives
    /// the chart-vs-empty-state branch. A week of pure zeros reads better as
    /// an explicit "nothing here yet" than as seven flat bars.
    private func hasActivity(_ rollup: WeeklyActivityRollup) -> Bool {
        rollup.daysWithLockout > 0
            || rollup.totalExtensionCount > 0
            || rollup.totalOverrideCount > 0
    }

    /// Native empty state for a quiet week (or before any data exists).
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No activity yet this week", systemImage: "chart.bar.xaxis")
        } description: {
            Text(
                "Once your curfew starts holding, each day's lockouts and the "
                    + "extensions or overrides you use will chart here."
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// Per-day Swift Charts visualisation. Stacked bars encode how many
    /// extensions and overrides were claimed each day (the "interventions
    /// used" the user is trying to reduce); the weekday axis label is tinted
    /// with the accent ember on days that held their lockout, so a single
    /// glance reads both "how consistently it held" and "how much I leaned on
    /// escapes". Counts share one y-axis; the boolean lockout signal rides the
    /// axis labels rather than competing for bar height.
    private func activityChart(rollup: WeeklyActivityRollup) -> some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            interventionBars(rollup: rollup)
                .chartForegroundStyleScale([
                    Self.extensionsLabel: CurfewTheme.accent,
                    Self.overridesLabel: CurfewTheme.warning
                ])
                .chartYAxis { weekdayCountAxis }
                .chartXAxis { weekdayLabelAxis(rollup: rollup) }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 160)

            lockoutLegend
        }
    }

    /// The stacked bar series: two bars per day (extensions + overrides),
    /// coloured by category via the foreground-style scale applied upstream.
    private func interventionBars(rollup: WeeklyActivityRollup) -> some View {
        Chart(interventionPoints(for: rollup)) { point in
            BarMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Count", point.count)
            )
            .foregroundStyle(by: .value("Type", point.category))
            .cornerRadius(4)
        }
    }

    /// Integer count ticks down the y-axis, in the muted ink so the bars stay
    /// the focal point.
    private var weekdayCountAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(CurfewTheme.border)
            AxisValueLabel {
                if let count = value.as(Int.self) {
                    Text("\(count)")
                        .font(CurfewTypography.label(11))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }
        }
    }

    /// Weekday labels along the x-axis, tinted with the accent ember on days
    /// that held their lockout so the boolean signal rides the axis rather than
    /// competing with the bars for height.
    private func weekdayLabelAxis(rollup: WeeklyActivityRollup) -> some AxisContent {
        let lockoutDays = Set(rollup.days.filter(\.hadLockout).map(\.day))
        return AxisMarks(values: rollup.days.map(\.day)) { value in
            if let date = value.as(Date.self) {
                AxisValueLabel {
                    Text(weekdayLabel(for: date))
                        .font(CurfewTypography.label(11))
                        .foregroundStyle(
                            lockoutDays.contains(date)
                                ? CurfewTheme.accent
                                : CurfewTheme.mutedInk
                        )
                }
            }
        }
    }

    /// Key for the accent-tinted axis labels — without it the highlight is just
    /// an unexplained colour. A tiny inline swatch carries the meaning.
    private var lockoutLegend: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CurfewTheme.accent)
                .frame(width: 8, height: 8)
            Text("Highlighted weekdays held their lockout.")
                .font(CurfewTypography.label(11))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    /// Flattens the weekly rollup into one chart row per (day, category) pair.
    /// Both categories are emitted for every day — including zero-count rows,
    /// which Charts renders as no bar — so the seven-day axis stays contiguous.
    private func interventionPoints(
        for rollup: WeeklyActivityRollup
    ) -> [DayIntervention] {
        rollup.days.flatMap { day in
            [
                DayIntervention(
                    day: day.day,
                    category: Self.extensionsLabel,
                    count: day.extensionCount
                ),
                DayIntervention(
                    day: day.day,
                    category: Self.overridesLabel,
                    count: day.overrideCount
                )
            ]
        }
    }

    /// Series label for extension bars. Hoisted to a constant so the chart
    /// data, the foreground-style scale, and the legend all agree on spelling.
    private static let extensionsLabel = "Extensions"
    /// Series label for override bars.
    private static let overridesLabel = "Overrides"

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

    /// Two-letter weekday label (Mo / Tu / …) in the user's locale.
    /// Uses the veryShort symbols for compactness — the full names don't
    /// fit in the seven-column grid at typical window widths.
    private func weekdayLabel(for date: Date) -> String {
        Self.weekdayFormatter.string(from: date)
    }

    /// A short list of today's calendar events, shown when Calendar is enabled + Pro.
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Schedule")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)

            ForEach(model.calendarMonitor.todayEvents.prefix(5), id: \.eventIdentifier) { event in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CurfewTheme.accent)
                        .frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "Event")
                            .font(CurfewTypography.bodyEmphasis(13))
                            .foregroundStyle(CurfewTheme.ink)
                        if let start = event.startDate, let end = event.endDate {
                            Text(
                                "\(start.formatted(date: .omitted, time: .shortened))"
                                    + " – \(end.formatted(date: .omitted, time: .shortened))"
                            )
                            .font(CurfewTypography.label(11))
                            .foregroundStyle(CurfewTheme.mutedInk)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

/// Split into its own extension so this CSV-export helper doesn't count
/// against `ThisWeekView`'s type-body-length budget.
private extension ThisWeekView {
    /// Opens an NSSavePanel and writes a CSV of this week's activity events.
    /// Warns instead of writing a silent empty file when the week has no
    /// recorded activity.
    func exportThisWeek() {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: model.currentTime)
        let weekday = cal.component(.weekday, from: startOfDay)
        let daysBack = (weekday - cal.firstWeekday + 7) % 7
        guard let weekStart = cal.date(byAdding: .day, value: -daysBack, to: startOfDay),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return }
        let range = weekStart ... weekEnd

        let csv = model.exportActivityCSV(in: range)

        guard csv.split(separator: "\n", omittingEmptySubsequences: true).count > 1 else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export yet"
            alert.informativeText = "There's no curfew activity recorded for this week."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "curfew-this-week.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Surface failure non-modally via the default error presenter.
                NSApp.presentError(error)
            }
        }
    }
}

/// One bar's worth of chart input: a day, a category ("Extensions" or
/// "Overrides"), and the count claimed that day. Two of these per day feed the
/// stacked ``BarMark`` series. `Identifiable` keeps `Chart(_:)` happy without a
/// manual `id:` key path.
private struct DayIntervention: Identifiable {
    let id = UUID()
    let day: Date
    let category: String
    let count: Int
}
