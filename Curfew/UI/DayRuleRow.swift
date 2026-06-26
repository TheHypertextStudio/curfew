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
/// - Bottom row: "Work ends" DatePicker → "->" → "Work resumes" DatePicker
///   (both disabled when day off).
///
/// Kept in its own file (rather than nested inside `SettingsView`) so this
/// file can hold all the date-⇄-minutes conversion helpers together and so
/// future per-row features (holiday pickers, per-day exceptions) have a
/// natural home.
struct DayRuleRow: View {
    /// Shared app model — used for both reads (`editableSchedule.rule(for:)`)
    /// and writes (`updateRule(for:update:)`).
    @EnvironmentObject private var model: CurfewAppModel

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

    /// Binding for the `CurfewMode` segmented picker. Flipping to `.hours`
    /// or `.combined` seeds a default `hoursLimitMinutes` (8 hours) when
    /// the user has not set one yet so the enforcement engine doesn't
    /// interpret `nil` as "no hours ceiling" and quietly disable the
    /// hours leg of combined mode.
    private func modeBinding() -> Binding<CurfewMode> {
        Binding(
            get: { dayRule.mode },
            set: { newMode in
                model.updateRule(for: weekday) { rule in
                    rule.mode = newMode
                    if newMode != .time, rule.hoursLimitMinutes == nil {
                        rule.hoursLimitMinutes = 8 * 60
                    }
                }
            }
        )
    }

    /// Binding for the "hours" value shown alongside the mode picker.
    /// Exposed in hours (not minutes) since that's what the user thinks
    /// in; the model stores minutes to keep the engine's math in one unit.
    private func hoursLimitBinding() -> Binding<Double> {
        Binding(
            get: {
                Double(dayRule.hoursLimitMinutes ?? 8 * 60) / 60
            },
            set: { newHours in
                let clamped = max(1.0, min(16.0, newHours))
                model.updateRule(for: weekday) { rule in
                    rule.hoursLimitMinutes = Int(clamped * 60)
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
                    Button("Apply to all") {
                        model.applyTimesToAllDays(
                            lockMinutes: dayRule.lockMinutes,
                            unlockMinutes: dayRule.unlockMinutes
                        )
                    }
                    .font(CurfewTypography.label(11))
                    .foregroundStyle(CurfewTheme.accent)
                    .buttonStyle(.plain)
                }
            }

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

                Text("→")
                    .font(CurfewTypography.body(16))
                    .foregroundStyle(CurfewTheme.mutedInk)

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

            if !dayRule.isDayOff {
                HStack(spacing: 10) {
                    Text("Trigger")
                        .font(CurfewTypography.label(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .frame(width: 48, alignment: .leading)

                    Picker("Mode", selection: modeBinding()) {
                        ForEach(CurfewMode.allCases, id: \.self) { mode in
                            Text(mode.shortName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    if dayRule.mode != .time {
                        Stepper(
                            value: hoursLimitBinding(),
                            in: 1.0 ... 16.0,
                            step: 0.5
                        ) {
                            Text("\(String(format: "%.1f", hoursLimitBinding().wrappedValue)) h")
                                .font(CurfewTypography.body(13))
                        }
                    }
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
