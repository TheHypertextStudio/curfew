import AppKit
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
            dayGrid(rollup: rollup)

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

    /// Opens an NSSavePanel and writes a CSV of this week's activity events.
    private func exportThisWeek() {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: model.currentTime)
        let weekday = cal.component(.weekday, from: startOfDay)
        let daysBack = (weekday - cal.firstWeekday + 7) % 7
        guard let weekStart = cal.date(byAdding: .day, value: -daysBack, to: startOfDay),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return }
        let range = weekStart ... weekEnd

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "curfew-this-week.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let csv = try model.exportActivityCSV(in: range)
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Surface failure non-modally via the default error presenter.
                NSApp.presentError(error)
            }
        }
    }
}
