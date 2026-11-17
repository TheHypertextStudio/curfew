import CurfewKit
import SwiftUI

/// One row of the weekly schedule editor — rendered for each `Weekday` by
/// `SettingsView.weeklySchedulePanel`. Owns its own bindings that round-
/// trip user edits through `CurfewAppModel.updateRule(for:update:)` so
/// the anti-bypass policy engine has a single entry point for schedule
/// mutations.
///
/// Rendered as a vertical pair of rows:
/// - Top row: weekday abbreviation + "day off" toggle.
/// - Bottom row: "Curfew" time → "Unlocks" time (hidden on a day off).
///
/// How the lock is triggered (at curfew, after hours worked, or both) is one
/// choice for the whole week in ``ScheduleLockRuleControl``, not per row.
///
/// Kept in its own file (rather than nested inside `SettingsView`) so this
/// file can hold all the date-⇄-minutes conversion helpers together and so
/// future per-row features (holiday pickers, per-day exceptions) have a
/// natural home.
struct DayRuleRow: View {
    /// Shared app model — used for both reads (`editableSchedule.rule(for:)`)
    /// and writes (`updateRule(for:update:)`).
    @Environment(CurfewAppModel.self) private var model

    /// Which weekday this row represents. Injected by the parent `ForEach`.
    let weekday: Weekday

    /// Current `DayRule` for this weekday, pulled through the model's
    /// `editableSchedule` so pending-but-not-yet-effective edits are
    /// visible in the editor (the engine still uses the live schedule
    /// until the cooldown expires).
    private var dayRule: DayRule {
        model.editableSchedule.rule(for: weekday)
    }

    /// Binding that adapts `DayRule.lockMinutes` (minute-of-day offset) to
    /// the `Date` that SwiftUI's `DatePicker` expects. Read/write
    /// round-tripped through `minutesToDate` / `dateToMinutes`.
    private func lockBinding() -> Binding<Date> {
        Binding(
            get: {
                minutesToDate(dayRule.lockMinutes)
            },
            set: { newValue in
                model.updateRule(for: weekday) { rule in
                    rule.lockMinutes = dateToMinutes(newValue)
                }
            }
        )
    }

    /// Symmetric binding for `DayRule.unlockMinutes`.
    private func unlockBinding() -> Binding<Date> {
        Binding(
            get: {
                minutesToDate(dayRule.unlockMinutes)
            },
            set: { newValue in
                model.updateRule(for: weekday) { rule in
                    rule.unlockMinutes = dateToMinutes(newValue)
                }
            }
        )
    }

    /// Binding for the "day off" toggle. A true day-off skips enforcement
    /// entirely for this weekday, regardless of lock/unlock values.
    private func dayOffBinding() -> Binding<Bool> {
        Binding(
            get: { dayRule.isDayOff },
            set: { isOff in
                model.updateRule(for: weekday) { rule in
                    rule.isDayOff = isOff
                }
            }
        )
    }

    /// SwiftUI body — weekday label + time pickers + mode switcher.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekday.shortName)
                    .font(CurfewTypography.title(15))
                    .frame(width: 52, alignment: .leading)

                Toggle("Day off", isOn: dayOffBinding())
                    .toggleStyle(.switch)
                    .font(CurfewTypography.body(13))

                Spacer()

                if !dayRule.isDayOff {
                    Button("Use for every day") {
                        model.applyTimesToAllDays(
                            lockMinutes: dayRule.lockMinutes,
                            unlockMinutes: dayRule.unlockMinutes
                        )
                    }
                    .font(CurfewTypography.label(11))
                    .foregroundStyle(CurfewTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(weekday.shortName) times for every day")
                }
            }

            if !dayRule.isDayOff {
                HStack(spacing: 10) {
                    Text(ScheduleSurfaceCopy.workEndsLabel)
                        .font(CurfewTypography.label(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .frame(width: 84, alignment: .leading)

                    DatePicker(
                        ScheduleSurfaceCopy.workEndsLabel,
                        selection: lockBinding(),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .disabled(dayRule.isDayOff)

                    Image(systemName: "arrow.right")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .accessibilityHidden(true)

                    Text(ScheduleSurfaceCopy.workResumesLabel)
                        .font(CurfewTypography.label(12))
                        .foregroundStyle(CurfewTheme.mutedInk)

                    DatePicker(
                        ScheduleSurfaceCopy.workResumesLabel,
                        selection: unlockBinding(),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .disabled(dayRule.isDayOff)
                }
            }
        }
        .padding(10)
        .background(
            CurfewTheme.surfaceMuted,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    /// Converts a "minutes since start of today" count to a `Date` at that
    /// offset. The date value returned is tied to today purely so
    /// `DatePicker` has a valid `Date` to display — only the hour/minute
    /// components of the returned value are meaningful.
    private func minutesToDate(_ minutes: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? Date()
    }

    /// Extracts hour + minute from a `Date` and collapses to a single
    /// minute-of-day integer (0–1439). Complementary to `minutesToDate`.
    private func dateToMinutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// The week's lock trigger, chosen once. Day rows only carry times.
enum ScheduleLockRule {
    static let mixedNote =
        "Your days use different rules. Choosing one here applies it to every working day."

    struct Current: Equatable {
        let mode: CurfewMode
        let hours: Double
        let isMixed: Bool
    }

    /// The trigger and work-hours limit the week currently uses, read from the
    /// first working day, and whether any working day differs from it.
    static func current(in schedule: WeeklySchedule) -> Current {
        let working = Weekday.allCases.map { schedule.rule(for: $0) }.filter { !$0.isDayOff }
        guard let first = working.first
        else { return Current(mode: .time, hours: 8, isMixed: false) }
        let hours = Double(first.hoursLimitMinutes ?? 8 * 60) / 60
        let isMixed = working.contains {
            $0.mode != first.mode ||
                ($0.mode != .time && $0.hoursLimitMinutes != first.hoursLimitMinutes)
        }
        return Current(mode: first.mode, hours: hours, isMixed: isMixed)
    }

    static func title(for mode: CurfewMode) -> String {
        switch mode {
        case .time: "At curfew"
        case .hours: "After hours worked"
        case .combined: "Whichever comes first"
        }
    }

    static func hoursText(_ hours: Double) -> String {
        let whole = Int(hours)
        let minutes = Int((hours - Double(whole)) * 60)
        let hourText = "\(whole) hour\(whole == 1 ? "" : "s")"
        return minutes == 0 ? hourText : "\(hourText) \(minutes) minutes"
    }
}

/// One advanced control for how every working day locks.
struct ScheduleLockRuleControl: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var isExpanded = false

    private var current: ScheduleLockRule.Current {
        ScheduleLockRule.current(in: model.editableSchedule)
    }

    var body: some View {
        let current = current
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("This Mac locks", selection: Binding(
                    get: { current.mode },
                    set: { apply(mode: $0, hours: current.hours) }
                )) {
                    ForEach(CurfewMode.allCases, id: \.self) { mode in
                        Text(ScheduleLockRule.title(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                if current.mode != .time {
                    Stepper(
                        value: Binding(
                            get: { current.hours },
                            set: { apply(mode: current.mode, hours: max(1, min(16, $0))) }
                        ),
                        in: 1 ... 16,
                        step: 0.5
                    ) {
                        Text("Work limit: \(ScheduleLockRule.hoursText(current.hours))")
                            .font(CurfewTypography.body(13))
                    }
                    .accessibilityLabel("Work limit")
                    .accessibilityValue(ScheduleLockRule.hoursText(current.hours))
                }
                if current.isMixed {
                    Text(ScheduleLockRule.mixedNote)
                        .font(CurfewTypography.body(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("When this Mac locks")
                    .font(CurfewTypography.bodyEmphasis(13))
                Spacer()
                Text(current.isMixed ? "Varies by day" : ScheduleLockRule.title(for: current.mode))
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    private func apply(mode: CurfewMode, hours: Double) {
        for weekday in Weekday.allCases where !model.editableSchedule.rule(for: weekday).isDayOff {
            model.updateRule(for: weekday) { rule in
                rule.mode = mode
                if mode != .time {
                    rule.hoursLimitMinutes = Int(hours * 60)
                }
            }
        }
    }
}
