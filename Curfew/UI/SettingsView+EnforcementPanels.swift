import CurfewKit
import SwiftUI

/// Enforcement-related panels for the Settings window: live enforcement
/// health, extension / override budgets, warning interval tuning, and
/// auto-shutdown toggles.
extension SettingsView {
    /// Surfaces the live ``EnforcementHealth`` verdict so a silently degraded
    /// lockout (revoked Accessibility, a downed keyboard-shield tap) is visible
    /// here, not just in the menu bar. When active it states so plainly in a
    /// section panel; when degraded it reuses the shared
    /// ``EnforcementHealthBanner`` (which brings its own panel chrome) so the
    /// remediation copy and fix-it button match the main window exactly. The
    /// fix-it action prompts for Accessibility and opens System Settings — both
    /// guarded against the test host inside the model.
    @ViewBuilder
    var enforcementHealthPanel: some View {
        if model.enforcementHealth.isFullyActive {
            Section {
                CurfewSectionTitle(
                    title: "Accessibility"
                )

                Label(
                    model.enforcementHealth.settingsStatusTitle,
                    systemImage: "checkmark.circle.fill"
                )
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.accent)

                Text(EnforcementHealth.activeSettingsDetail)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            EnforcementHealthBanner(health: model.enforcementHealth) {
                model.requestAccessibilityAccess()
            }
        }
    }

    /// Controls weekly extension and override counts + their durations.
    /// The ranges bound each stepper to values that don't break downstream
    /// invariants (e.g. overrides have a 15-minute floor so the "convince
    /// me" grant is meaningful).
    var extensionsPanel: some View {
        @Bindable var model = model
        return Section {
            CurfewSectionTitle(title: "Extensions and Overrides")

            allowanceControls(
                title: "Extensions", detail: "Delay scheduled lockout.",
                weeklyLimit: $model.settings.extensionWeeklyLimit,
                duration: $model.settings.extensionDurationMinutes,
                minimumDuration: 5
            )
            allowanceControls(
                title: "Overrides", detail: "Temporarily unlock during lockout.",
                weeklyLimit: $model.settings.overrideWeeklyLimit,
                duration: $model.settings.overrideDurationMinutes,
                minimumDuration: 15
            )

            Divider()

            Picker("Weekly reset day", selection: $model.settings.resetWeekday) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

            Text("Extension and override budgets refresh on this day each week.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func allowanceControls(
        title: String, detail: String, weeklyLimit: Binding<Int>, duration: Binding<Int>,
        minimumDuration: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(CurfewTypography.bodyEmphasis(13))
                Text(detail)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 24) {
                SettingsValueRow(
                    title: "Per week", value: weeklyLimit, range: 0 ... 10,
                    accessibilityTitle: "\(title) per week"
                )
                SettingsValueRow(
                    title: "Duration", value: duration, range: minimumDuration ... 60,
                    step: 5, usesMinutes: true, accessibilityTitle: "\(title) duration"
                )
            }
        }
        .padding(.vertical, 4)
    }

    /// Five steppers for the T-30 / T-15 / T-5 / T-2 / T-1 warning stages.
    ///
    /// Each stepper's range is constrained so the relative ordering
    /// (earlier → later) is preserved without the user having to think
    /// about it. `warningBinding(get:set:)` wraps the model mutation so
    /// every edit goes through `WarningIntervals.normalized` before
    /// persisting.
    var warningPanel: some View {
        Section {
            CurfewSectionTitle(title: "Warning Intervals")

            let intervals = model.settings.warningIntervals
            let minutes = [
                intervals.thirtyMinutes, intervals.fifteenMinutes, intervals.fiveMinutes,
                intervals.twoMinutes, intervals.oneMinute
            ].map(String.init).joined(separator: ", ")
            Text("Warnings before lockout: \(minutes) min")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Change warning times", isExpanded: $showsWarningTimes) {
                warningControls
                    .padding(.top, 8)
            }
        }
    }

    private var warningControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            Text("Time before lockout")
                .font(CurfewTypography.label())
                .foregroundStyle(CurfewTheme.mutedInk)
            SettingsValueRow(
                title: "First warning", value: warningBinding(
                    get: { $0.thirtyMinutes }, set: { $0.thirtyMinutes = $1 }
                ), range: (model.settings.warningIntervals.fifteenMinutes + 1) ... 360,
                usesMinutes: true
            )
            SettingsValueRow(
                title: "Second warning", value: warningBinding(
                    get: { $0.fifteenMinutes }, set: { $0.fifteenMinutes = $1 }
                ), range: (model.settings.warningIntervals.fiveMinutes + 1) ...
                    (model.settings.warningIntervals.thirtyMinutes - 1), usesMinutes: true
            )
            SettingsValueRow(
                title: "Third warning", value: warningBinding(
                    get: { $0.fiveMinutes }, set: { $0.fiveMinutes = $1 }
                ), range: (model.settings.warningIntervals.twoMinutes + 1) ...
                    (model.settings.warningIntervals.fifteenMinutes - 1), usesMinutes: true
            )
            SettingsValueRow(
                title: "Fourth warning", value: warningBinding(
                    get: { $0.twoMinutes }, set: { $0.twoMinutes = $1 }
                ), range: (model.settings.warningIntervals.oneMinute + 1) ...
                    (model.settings.warningIntervals.fiveMinutes - 1), usesMinutes: true
            )
            SettingsValueRow(
                title: "Final warning", value: warningBinding(
                    get: { $0.oneMinute }, set: { $0.oneMinute = $1 }
                ), range: 1 ... (model.settings.warningIntervals.twoMinutes - 1), usesMinutes: true
            )
        }
    }

    /// Toggle + delay stepper controlling whether Curfew tries to shut the
    /// Mac down after lockout begins.
    var shutdownPanel: some View {
        @Bindable var model = model
        return Section {
            CurfewSectionTitle(title: "Automatic Shutdown")
            switch ShutdownPanelState.resolve(isAvailable: SystemShutdownController.isAvailable) {
            case .available:
                SettingsToggleRow(
                    title: "Enable auto shutdown",
                    isOn: $model.settings.autoShutdownEnabled
                )

                SettingsValueRow(
                    title: "Shutdown delay", value: $model.settings.autoShutdownDelayMinutes,
                    range: 1 ... 60, usesMinutes: true
                )
                .disabled(!model.settings.autoShutdownEnabled)

                Text(ShutdownPanelState.availableExplanation)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable(let message):
                Text(message)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Builds a `Binding<Int>` that round-trips changes through
    /// `WarningIntervals.normalized`, so user edits can never produce an
    /// invalid (non-monotonic) interval set.
    ///
    /// - Parameters:
    ///   - get: extract the current value for a specific interval.
    ///   - set: mutate the given `WarningIntervals` to apply a new value.
    func warningBinding(
        get: @escaping (WarningIntervals) -> Int,
        set: @escaping (inout WarningIntervals, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: {
                get(model.settings.warningIntervals)
            },
            set: { newValue in
                var intervals = model.settings.warningIntervals
                set(&intervals, newValue)
                model.settings.warningIntervals = intervals.normalized
            }
        )
    }
}
