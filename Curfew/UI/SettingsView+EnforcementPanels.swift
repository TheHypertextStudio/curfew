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
        } else if model.enforcementHealth.offersAccessibilityRemediation {
            EnforcementHealthBanner(health: model.enforcementHealth) {
                model.requestAccessibilityAccess()
            }
        }
        // Helper problems are stated once, in the Curfew helper row below.
    }

    /// Controls weekly extension and override counts + their durations.
    /// The ranges bound each stepper to values that don't break downstream
    /// invariants (e.g. overrides have a 15-minute floor so the "convince
    /// me" grant is meaningful).
    var extensionsPanel: some View {
        @Bindable var model = model
        return Section {
            CurfewSectionTitle(title: "More time and overrides")

            allowanceControls(
                title: "More time", detail: "Pushes curfew back.",
                weeklyLimit: $model.settings.extensionWeeklyLimit,
                duration: $model.settings.extensionDurationMinutes,
                minimumDuration: 5
            )
            allowanceControls(
                title: "Overrides", detail: "Gets you back in after the lock.",
                weeklyLimit: $model.settings.overrideWeeklyLimit,
                duration: $model.settings.overrideDurationMinutes,
                minimumDuration: 15
            )

            Picker("Week starts on", selection: $model.settings.resetWeekday) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

            Text("More time and overrides refill on this day.")
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

    /// Five steppers for the five warning stages, kept behind one disclosure
    /// because the stored model has five independent times.
    ///
    /// Each stepper's range is constrained so the relative ordering
    /// (earlier → later) is preserved without the user having to think
    /// about it. `warningBinding(get:set:)` wraps the model mutation so
    /// every edit goes through `WarningIntervals.normalized` before
    /// persisting.
    var warningPanel: some View {
        Section {
            CurfewSectionTitle(title: "Warnings")

            Text(SettingsCopy.warningSummary(model.settings.warningIntervals))
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
            Text("Minutes before curfew")
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
            CurfewSectionTitle(title: "Shut down after curfew")
            switch ShutdownPanelState.resolve(isAvailable: SystemShutdownController.isAvailable) {
            case .available:
                SettingsToggleRow(
                    title: "Shut down this Mac after curfew",
                    isOn: Binding(
                        get: { model.settings.autoShutdownEnabled },
                        set: { enabled in
                            model.settings.autoShutdownEnabled = enabled
                            if enabled { askForShutdownPermission() }
                        }
                    )
                )

                SettingsValueRow(
                    title: "Wait before shutting down",
                    value: $model.settings.autoShutdownDelayMinutes,
                    range: 1 ... 60, usesMinutes: true
                )
                .disabled(!model.settings.autoShutdownEnabled)

                Text(SettingsCopy.shutdownPermissionReason)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                if shutdownPermission == .denied {
                    HStack(spacing: 10) {
                        Label(SettingsCopy.shutdownPermissionDenied,
                              systemImage: "exclamationmark.triangle.fill")
                            .font(CurfewTypography.body(13))
                            .foregroundStyle(CurfewTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Open Automation settings") {
                            ShutdownAutomationPermission.openSystemSettings()
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            case .unavailable(let message):
                Text(message)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Asks macOS for Automation access the moment shutdown is switched on,
    /// so the prompt never first appears at night during a real shutdown.
    func askForShutdownPermission() {
        guard !model.isDemoSession else { return }
        Task {
            shutdownPermission = await ShutdownAutomationPermission.request()
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
