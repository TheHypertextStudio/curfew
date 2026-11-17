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
        let health = model.enforcementHealth
        if health.isFullyActive {
            SettingsGroup("Accessibility") {
                SettingsActionRow(
                    title: health.settingsStatusTitle,
                    detail: EnforcementHealth.activeSettingsDetail,
                    actionTitle: nil
                )
            }
        } else if health.offersAccessibilityRemediation {
            SettingsGroup("Accessibility") {
                SettingsActionRow(
                    title: health.settingsStatusTitle,
                    detail: health.bannerDetail,
                    tone: .warning,
                    actionTitle: "Restore shortcut blocking"
                ) {
                    model.requestAccessibilityAccess()
                }
            }
        }
        // Helper problems are stated once, in the Curfew helper row below.
    }

    /// Weekly counts and lengths of more time and overrides. The ranges bound
    /// each stepper to values that don't break downstream invariants (overrides
    /// have a 15-minute floor).
    var extensionsPanel: some View {
        @Bindable var model = model
        return SettingsGroup("More time and overrides") {
            SettingsValueRow(
                title: "More time per week", detail: "Each one pushes curfew back.",
                value: $model.settings.extensionWeeklyLimit, range: 0 ... 10
            )
            SettingsValueRow(
                title: "Length of more time",
                value: $model.settings.extensionDurationMinutes, range: 5 ... 60,
                step: 5, usesMinutes: true
            )
            SettingsValueRow(
                title: "Overrides per week", detail: "Each one gets you back in after the lock.",
                value: $model.settings.overrideWeeklyLimit, range: 0 ... 10
            )
            SettingsValueRow(
                title: "Length of an override",
                value: $model.settings.overrideDurationMinutes, range: 15 ... 60,
                step: 5, usesMinutes: true
            )
            SettingsPickerRow(
                title: "Week starts on",
                detail: "More time and overrides refill on this day.",
                selection: $model.settings.resetWeekday,
                segmented: true
            ) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
        }
    }

    /// Five steppers for the five warning stages, kept behind one disclosure
    /// because the stored model has five independent times. Every edit goes
    /// through `WarningIntervals.normalized` so the order is always preserved.
    var warningPanel: some View {
        SettingsGroup("Warnings") {
            DisclosureGroup(isExpanded: $showsWarningTimes) {
                warningControls
                    .padding(.top, 4)
            } label: {
                SettingsRowLabel(
                    title: "Warning times",
                    detail: SettingsCopy.warningSummary(model.settings.warningIntervals)
                )
            }
        }
    }

    private var warningControls: some View {
        let intervals = model.settings.warningIntervals
        return VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            SettingsValueRow(
                title: "First warning", value: warningBinding(
                    get: { $0.thirtyMinutes }, set: { $0.thirtyMinutes = $1 }
                ), range: (intervals.fifteenMinutes + 1) ... 360, usesMinutes: true
            )
            SettingsValueRow(
                title: "Second warning", value: warningBinding(
                    get: { $0.fifteenMinutes }, set: { $0.fifteenMinutes = $1 }
                ), range: (intervals.fiveMinutes + 1) ... (intervals.thirtyMinutes - 1),
                usesMinutes: true
            )
            SettingsValueRow(
                title: "Third warning", value: warningBinding(
                    get: { $0.fiveMinutes }, set: { $0.fiveMinutes = $1 }
                ), range: (intervals.twoMinutes + 1) ... (intervals.fifteenMinutes - 1),
                usesMinutes: true
            )
            SettingsValueRow(
                title: "Fourth warning", value: warningBinding(
                    get: { $0.twoMinutes }, set: { $0.twoMinutes = $1 }
                ), range: (intervals.oneMinute + 1) ... (intervals.fiveMinutes - 1),
                usesMinutes: true
            )
            SettingsValueRow(
                title: "Final warning", value: warningBinding(
                    get: { $0.oneMinute }, set: { $0.oneMinute = $1 }
                ), range: 1 ... (intervals.twoMinutes - 1), usesMinutes: true
            )
        }
    }

    /// Whether Curfew shuts this Mac down after the lock, and how long it waits.
    var shutdownPanel: some View {
        @Bindable var model = model
        return SettingsGroup("Shut down after curfew") {
            switch ShutdownPanelState.resolve(isAvailable: SystemShutdownController.isAvailable) {
            case .available:
                SettingsToggleRow(
                    title: "Shut down this Mac after curfew",
                    detail: SettingsCopy.shutdownPermissionReason,
                    isOn: Binding(
                        get: { model.settings.autoShutdownEnabled },
                        set: { enabled in
                            model.settings.autoShutdownEnabled = enabled
                            if enabled {
                                askForShutdownPermission()
                            }
                        }
                    )
                )
                if shutdownPermission == .denied {
                    SettingsActionRow(
                        title: SettingsCopy.shutdownPermissionDenied,
                        tone: .warning,
                        actionTitle: "Open Automation settings"
                    ) {
                        ShutdownAutomationPermission.openSystemSettings()
                    }
                }
                SettingsValueRow(
                    title: "Wait before shutting down",
                    value: $model.settings.autoShutdownDelayMinutes,
                    range: 1 ... 60, usesMinutes: true
                )
                .disabled(!model.settings.autoShutdownEnabled)
            case .unavailable(let message):
                SettingsActionRow(
                    title: "Shut down this Mac after curfew",
                    detail: message,
                    actionTitle: nil
                )
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
