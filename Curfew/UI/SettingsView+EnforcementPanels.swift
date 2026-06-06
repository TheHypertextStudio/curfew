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
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Enforcement Health",
                    subtitle: model.enforcementHealth.settingsStatusTitle
                )

                Label("Enforcement is active", systemImage: "checkmark.circle.fill")
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
        CurfewPanel {
            CurfewSectionTitle(title: "Extensions and Overrides")

            Stepper(
                "Extensions per week: \(model.settings.extensionWeeklyLimit)",
                value: $model.settings.extensionWeeklyLimit,
                in: 0 ... 10
            )

            Stepper(
                "Extension duration: \(model.settings.extensionDurationMinutes) min",
                value: $model.settings.extensionDurationMinutes,
                in: 5 ... 60,
                step: 5
            )

            Stepper(
                "Overrides per week: \(model.settings.overrideWeeklyLimit)",
                value: $model.settings.overrideWeeklyLimit,
                in: 0 ... 10
            )

            Stepper(
                "Override duration: \(model.settings.overrideDurationMinutes) min",
                value: $model.settings.overrideDurationMinutes,
                in: 15 ... 60,
                step: 5
            )
        }
    }

    /// Five steppers for the T-30 / T-15 / T-5 / T-2 / T-1 warning stages.
    ///
    /// Each stepper's range is constrained so the relative ordering
    /// (earlier → later) is preserved without the user having to think
    /// about it. `warningBinding(get:set:)` wraps the model mutation so
    /// every edit goes through `WarningIntervals.normalized` before
    /// persisting.
    var warningPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Warning Intervals")

            Stepper(
                "\(model.settings.warningIntervals.thirtyMinutes) min before lockout",
                value: warningBinding(
                    get: { $0.thirtyMinutes },
                    set: { $0.thirtyMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.fifteenMinutes + 1) ... 360
            )

            Stepper(
                "\(model.settings.warningIntervals.fifteenMinutes) min before lockout",
                value: warningBinding(
                    get: { $0.fifteenMinutes },
                    set: { $0.fifteenMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.fiveMinutes + 1) ...
                    (model.settings.warningIntervals.thirtyMinutes - 1)
            )

            Stepper(
                "\(model.settings.warningIntervals.fiveMinutes) min before lockout",
                value: warningBinding(
                    get: { $0.fiveMinutes },
                    set: { $0.fiveMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.twoMinutes + 1) ...
                    (model.settings.warningIntervals.fifteenMinutes - 1)
            )

            Stepper(
                "\(model.settings.warningIntervals.twoMinutes) min before lockout",
                value: warningBinding(
                    get: { $0.twoMinutes },
                    set: { $0.twoMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.oneMinute + 1) ...
                    (model.settings.warningIntervals.fiveMinutes - 1)
            )

            Stepper(
                "\(model.settings.warningIntervals.oneMinute) min before lockout",
                value: warningBinding(
                    get: { $0.oneMinute },
                    set: { $0.oneMinute = $1 }
                ),
                in: 1 ... (model.settings.warningIntervals.twoMinutes - 1)
            )
        }
    }

    /// Toggle + delay stepper controlling whether Curfew tries to shut the
    /// Mac down after lockout begins.
    var shutdownPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Shutdown")
            switch ShutdownPanelState.resolve(isAvailable: SystemShutdownController.isAvailable) {
            case .available:
                Toggle("Enable auto shutdown", isOn: $model.settings.autoShutdownEnabled)

                Stepper(
                    "Shutdown delay: \(model.settings.autoShutdownDelayMinutes) min",
                    value: $model.settings.autoShutdownDelayMinutes,
                    in: 1 ... 60
                )

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
