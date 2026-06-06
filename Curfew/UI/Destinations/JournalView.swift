import SwiftUI

/// "Journal" workspace destination — the reflective archive.
///
/// A thin adapter: folds the weekly rollup into the sundown week chart
/// (``JournalSundownView``), marking each night kept / override / day off /
/// upcoming. The nightly reflection entries land below this in a later phase.
struct JournalView: View {
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        let rollup = model.thisWeekRollup()
        ScrollView {
            JournalSundownView(
                dateRange: Self.dateRange(for: rollup),
                nights: Self.nights(
                    for: rollup,
                    schedule: model.editableSchedule,
                    now: model.currentTime
                ),
                footnote: Self.footnote(for: rollup)
            )
        }
        .scrollIndicators(.hidden)
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
