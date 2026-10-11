import CurfewKit
import SwiftUI

extension SettingsView {
    var enforcementHealthPanel: some View {
        Section("Protection") {
            if model.enforcementHealth.isFullyActive {
                LabeledContent("Lockout", value: model.enforcementHealth.settingsStatusTitle)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        model.enforcementHealth.settingsStatusTitle,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .fontWeight(.medium)
                    Text(model.enforcementHealth.bannerDetail ?? "")
                        .font(.callout)
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.enforcementHealth.offersAccessibilityRemediation {
                        Button("Open Accessibility Settings") { model.requestAccessibilityAccess() }
                            .buttonStyle(.bordered)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    var extensionsPanel: some View {
        @Bindable var model = model
        return Group {
            Section {
                WeeklyBudgetSteppers(model: model)
                Picker("Resets on", selection: $model.settings.resetWeekday) {
                    ForEach(Weekday.allCases) { day in Text(day.shortName).tag(day) }
                }
            } header: {
                Text("Weekly allowance")
            } footer: {
                Text(
                    "Extensions add time before lockout. Overrides let you return after it starts."
                )
            }
            Section("Extra time") {
                if model.settings.extensionWeeklyLimit > 0 {
                    Stepper(
                        value: $model.settings.extensionDurationMinutes,
                        in: 5 ... 60,
                        step: 5
                    ) {
                        LabeledContent(
                            "Each extension",
                            value: "\(model.settings.extensionDurationMinutes) min"
                        )
                    }
                }
                if model.settings.overrideWeeklyLimit > 0 {
                    Stepper(
                        value: $model.settings.overrideDurationMinutes,
                        in: 15 ... 60,
                        step: 5
                    ) {
                        LabeledContent(
                            "Each override",
                            value: "\(model.settings.overrideDurationMinutes) min"
                        )
                    }
                }
                if model.settings.extensionWeeklyLimit == 0,
                   model.settings.overrideWeeklyLimit == 0 {
                    Text("No extra time allowed.").foregroundStyle(CurfewTheme.mutedInk)
                }
            }
        }
    }

    var warningPanel: some View {
        Section {
            warningRow(
                "First reminder",
                get: { $0.thirtyMinutes },
                set: { $0.thirtyMinutes = $1 },
                range: (model.settings.warningIntervals.fifteenMinutes + 1) ... 360
            )
            warningRow(
                "Second reminder",
                get: { $0.fifteenMinutes },
                set: { $0.fifteenMinutes = $1 },
                range: (model.settings.warningIntervals.fiveMinutes + 1) ...
                    (model.settings.warningIntervals.thirtyMinutes - 1)
            )
            warningRow(
                "Wrap up",
                get: { $0.fiveMinutes },
                set: { $0.fiveMinutes = $1 },
                range: (model.settings.warningIntervals.twoMinutes + 1) ...
                    (model.settings.warningIntervals.fifteenMinutes - 1)
            )
            warningRow(
                "Final warning",
                get: { $0.twoMinutes },
                set: { $0.twoMinutes = $1 },
                range: (model.settings.warningIntervals.oneMinute + 1) ...
                    (model.settings.warningIntervals.fiveMinutes - 1)
            )
            warningRow(
                "Last minute",
                get: { $0.oneMinute },
                set: { $0.oneMinute = $1 },
                range: 1 ... (model.settings.warningIntervals.twoMinutes - 1)
            )
        } header: {
            Text("Before lockout")
        } footer: {
            Text("Minutes before your Mac locks.")
        }
    }

    private func warningRow(
        _ title: String, get: @escaping (WarningIntervals) -> Int,
        set: @escaping (inout WarningIntervals, Int) -> Void, range: ClosedRange<Int>
    ) -> some View {
        Stepper(value: warningBinding(get: get, set: set), in: range) {
            LabeledContent(title, value: "\(get(model.settings.warningIntervals)) min")
        }
    }

    var shutdownPanel: some View {
        @Bindable var model = model
        return Section("After lockout") {
            switch ShutdownPanelState.resolve(isAvailable: SystemShutdownController.isAvailable) {
            case .available:
                Toggle("Shut down this Mac", isOn: $model.settings.autoShutdownEnabled)
                if model.settings.autoShutdownEnabled {
                    Stepper(value: $model.settings.autoShutdownDelayMinutes, in: 1 ... 60) {
                        LabeledContent(
                            "Delay",
                            value: "\(model.settings.autoShutdownDelayMinutes) min"
                        )
                    }
                    Text(
                        "Save your work before lockout. macOS will ask for permission to shut down."
                    )
                    .foregroundStyle(CurfewTheme.mutedInk)
                    DisclosureGroup("Permission help") {
                        Text(ShutdownPanelState.availableExplanation)
                    }
                }
            case .unavailable(let message):
                Text(message).foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    /// Which applications shutdown must leave alone, and how long a live
    /// work claim may hold shutdown back.
    ///
    /// The list is one identifier per line because that is the shape people
    /// already paste bundle identifiers in, and a table with add/remove
    /// buttons would be more chrome than a list edited twice a year deserves.
    var protectedWorkPanel: some View {
        @Bindable var model = model
        return Section("Work during lockout") {
            Toggle(
                "Wait for remote sessions",
                isOn: $model.settings.protectedWork.defersForRemoteSessions
            )
            Toggle(
                "Accept work declared by AI assistants",
                isOn: $model.settings.protectedWork.acceptsAgentClaims
            )
            Stepper(
                value: $model.settings.protectedWork.maximumDeferralMinutes,
                in: 1 ... ProtectedWorkPolicy.deferralCeilingMinutes,
                step: 5
            ) {
                LabeledContent(
                    "Maximum wait",
                    value: "\(model.settings.protectedWork.maximumDeferralMinutes) min"
                )
            }
            Text("Work can delay shutdown until this limit. The screen stays locked.")
                .foregroundStyle(CurfewTheme.mutedInk)
            DisclosureGroup("Applications and commands") {
                Text(
                    "These apps are excluded from Curfew's quit requests. "
                        + "A completed shutdown still stops all work."
                )
                .foregroundStyle(CurfewTheme.mutedInk)
                Text("App bundle identifiers, one per line")
                TextEditor(text: protectedListBinding(\.protectedBundleIdentifiers))
                    .font(.system(.body, design: .monospaced)).frame(minHeight: 88)
                Text("Process names excluded from quit requests, one per line")
                TextEditor(text: protectedListBinding(\.protectedProcessNames))
                    .font(.system(.body, design: .monospaced)).frame(minHeight: 88)
                Text("Wait while these commands run, one per line")
                TextEditor(text: protectedListBinding(\.deferringProcessNames))
                    .font(.system(.body, design: .monospaced)).frame(minHeight: 88)
                Text(
                    "Use commands that finish on their own; "
                        + "a terminal or tmux server may run all night."
                )
                .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    /// Bridges a newline-separated text editor to a `[String]` on the policy,
    /// dropping blank lines and surrounding whitespace on the way in.
    func protectedListBinding(
        _ keyPath: WritableKeyPath<ProtectedWorkPolicy, [String]>
    ) -> Binding<String> {
        Binding(
            get: { model.settings.protectedWork[keyPath: keyPath].joined(separator: "\n") },
            set: { newValue in
                model.settings.protectedWork[keyPath: keyPath] = newValue
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
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
        Binding(get: { get(model.settings.warningIntervals) }, set: { value in
            var intervals = model.settings.warningIntervals
            set(&intervals, value)
            model.settings.warningIntervals = intervals.normalized
        })
    }
}
