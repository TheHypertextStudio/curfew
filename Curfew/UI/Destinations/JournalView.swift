import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Journal" workspace destination — the reflective archive: the week's sundown
/// chart (``JournalSundownView``), the neutral rating trends and per-entry
/// reflections (``JournalReflectionsView``), and an export menu (Markdown /
/// JSON / Share) for getting a week's journal out of the app.
struct JournalView: View {
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        let rollup = model.thisWeekRollup()
        ScrollView {
            VStack(spacing: 0) {
                JournalSundownView(
                    dateRange: Self.dateRange(for: rollup),
                    nights: Self.nights(
                        for: rollup,
                        schedule: model.editableSchedule,
                        now: model.currentTime
                    ),
                    footnote: Self.footnote(for: rollup)
                )

                JournalReflectionsView(
                    reflections: model.reflections(inWeekOf: model.currentTime),
                    referenceDate: model.currentTime
                )
            }
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .topTrailing) {
            exportMenu
                .padding(.top, 28)
                .padding(.trailing, 28)
        }
    }

    /// Export affordance floated over the Journal header: save a Markdown or
    /// JSON file, or share/copy this week's journal. Mirrors the NSSavePanel
    /// pattern in ``ThisWeekView``.
    private var exportMenu: some View {
        Menu {
            Button("Export as Markdown…") { exportReflections(asJSON: false) }
            Button("Export as JSON…") { exportReflections(asJSON: true) }
            Divider()
            Button("Copy this week") {
                let markdown = model.exportReflectionsMarkdown(inWeekOf: model.currentTime)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
            ShareLink(
                "Share this week",
                item: model.exportReflectionsMarkdown(inWeekOf: model.currentTime)
            )
        } label: {
            Image(systemName: "square.and.arrow.up")
                .imageScale(.large)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Export or share this week's reflections")
        .accessibilityLabel("Export reflections")
    }

    /// Opens an NSSavePanel and writes this week's reflections as Markdown or
    /// JSON. Defaults the filename per format; failures surface non-modally.
    private func exportReflections(asJSON: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = asJSON
            ? [.json]
            : [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = asJSON
            ? "curfew-reflections.json"
            : "curfew-reflections.md"
        let now = model.currentTime
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = asJSON
                ? model.exportReflectionsJSON(inWeekOf: now)
                : model.exportReflectionsMarkdown(inWeekOf: now)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    private static func nights(
        for rollup: WeeklyActivityRollup,
        schedule: WeeklySchedule,
        now: Date
    ) -> [(day: String, state: JournalSundownView.NightState)] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        return rollup.days.map { daily in
            (
                day: narrowDayFormatter.string(from: daily.day),
                state: state(
                    for: daily,
                    schedule: schedule,
                    todayStart: todayStart,
                    calendar: calendar
                )
            )
        }
    }

    private static func state(
        for daily: DailyActivityRollup,
        schedule: WeeklySchedule,
        todayStart: Date,
        calendar: Calendar
    ) -> JournalSundownView.NightState {
        if calendar.startOfDay(for: daily.day) >= todayStart {
            return .upcoming
        }
        if schedule.rule(for: daily.day).isDayOff {
            return .off
        }
        if daily.overrideCount > 0 {
            return .overridden
        }
        if daily.hadLockout {
            return .kept
        }
        return .off
    }

    private static func footnote(for rollup: WeeklyActivityRollup) -> String {
        let extensions = rollup.totalExtensionCount
        let overrides = rollup.totalOverrideCount
        let extLabel = "\(extensions) extension\(extensions == 1 ? "" : "s")"
        let ovrLabel = "\(overrides) override\(overrides == 1 ? "" : "s")"
        return "\(extLabel), \(ovrLabel) this week"
    }

    private static func dateRange(for rollup: WeeklyActivityRollup) -> String {
        guard let first = rollup.days.first?.day, let last = rollup.days.last?.day else {
            return "This week"
        }
        return "\(monthDayFormatter.string(from: first))–\(dayFormatter.string(from: last))"
    }

    private static let narrowDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}
