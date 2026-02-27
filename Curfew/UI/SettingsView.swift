import SwiftUI
import Foundation

enum GettingStartedCopy {
    static let title = "Welcome to Curfew"
    static let commitmentMessage = "Set your schedule while you're thinking clearly, then let Curfew enforce it later."
    static let setupFocusTitle = "What to Configure First"
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case schedule
    case enforcement
    case integrations
    case devices
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule:
            return "Schedule"
        case .enforcement:
            return "Enforcement"
        case .integrations:
            return "Integrations"
        case .devices:
            return "Devices"
        case .advanced:
            return "Advanced"
        }
    }
}

enum FirstRunStep: Int, CaseIterable, Identifiable {
    case welcome
    case schedule
    case extensionBudget
    case permissions
    case confirmation

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .schedule:
            return "Schedule"
        case .extensionBudget:
            return "Extension Budget"
        case .permissions:
            return "Permissions"
        case .confirmation:
            return "Confirmation"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Curfew helps you keep commitments you made while you had clear focus."
        case .schedule:
            return "Choose realistic lock and unlock times for each day so your plan matches your week."
        case .extensionBudget:
            return "Set weekly extension and override limits to keep exceptions deliberate."
        case .permissions:
            return "Curfew uses notifications and accessibility APIs so warnings and lockout behavior work reliably."
        case .confirmation:
            return "Review your setup, then enable Curfew when you are ready."
        }
    }

    var checklist: [String] {
        switch self {
        case .welcome:
            return ["Understand how Curfew enforces commitments"]
        case .schedule:
            return ["Set lock and unlock times", "Mark true days off"]
        case .extensionBudget:
            return ["Adjust weekly extension limit", "Set override duration"]
        case .permissions:
            return ["Allow notifications", "Confirm accessibility permissions"]
        case .confirmation:
            return ["Enable Curfew", "Start with confidence"]
        }
    }
}

struct FirstRunFlow {
    private(set) var currentStep: FirstRunStep = .welcome

    var isFirstStep: Bool {
        currentStep == .welcome
    }

    var isLastStep: Bool {
        currentStep == .confirmation
    }

    mutating func advance() {
        guard let nextStep = FirstRunStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        currentStep = nextStep
    }

    mutating func retreat() {
        guard let previousStep = FirstRunStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @State private var selectedSection: SettingsSection = .schedule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionSelector
                sectionContent
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(CurfewTheme.canvas)
        .tint(CurfewTheme.accent)
        .foregroundStyle(CurfewTheme.ink)
    }

    private var settingsSectionSelector: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Settings",
                subtitle: "Choose a section to configure Curfew."
            )

            HStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { section in
                    if selectedSection == section {
                        Button(section.title) {
                            selectedSection = section
                        }
                        .buttonStyle(CurfewPrimaryButtonStyle())
                    } else {
                        Button(section.title) {
                            selectedSection = section
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .schedule:
            presetsPanel
            weeklySchedulePanel
            if let pending = model.pendingScheduleDescription {
                pendingChangePanel(message: pending)
            }
        case .enforcement:
            extensionsPanel
            warningPanel
            shutdownPanel
        case .integrations:
            integrationsPanel
        case .devices:
            devicesPanel
        case .advanced:
            advancedPanel
            setupPanel
        }
    }

    private func pendingChangePanel(message: String) -> some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Pending Change")
            Text(message)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.warning)
        }
    }

    private var presetsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Presets",
                subtitle: "Start from a baseline and tweak day-by-day."
            )

            HStack(spacing: 10) {
                ForEach(SchedulePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.applyPreset(preset)
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
        }
    }

    private var weeklySchedulePanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Weekly Schedule",
                subtitle: "Set lock and unlock times for each day."
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Weekday.allCases) { weekday in
                    DayRuleRow(weekday: weekday)
                    if weekday != Weekday.allCases.last {
                        Divider()
                    }
                }
            }

            Text(model.scheduleSummarySentence)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    private var extensionsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Extensions and Overrides")

            Stepper(
                "Extensions per week: \(model.settings.extensionWeeklyLimit)",
                value: $model.settings.extensionWeeklyLimit,
                in: 0...10
            )

            Stepper(
                "Extension duration: \(model.settings.extensionDurationMinutes) min",
                value: $model.settings.extensionDurationMinutes,
                in: 5...60,
                step: 5
            )

            Stepper(
                "Overrides per week: \(model.settings.overrideWeeklyLimit)",
                value: $model.settings.overrideWeeklyLimit,
                in: 0...10
            )

            Stepper(
                "Override duration: \(model.settings.overrideDurationMinutes) min",
                value: $model.settings.overrideDurationMinutes,
                in: 15...60,
                step: 5
            )
        }
    }

    private var warningPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Warning Intervals")

            Stepper(
                "T-\(model.settings.warningIntervals.thirtyMinutes) warning",
                value: warningBinding(
                    get: { $0.thirtyMinutes },
                    set: { $0.thirtyMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.fifteenMinutes + 1)...360
            )

            Stepper(
                "T-\(model.settings.warningIntervals.fifteenMinutes) warning",
                value: warningBinding(
                    get: { $0.fifteenMinutes },
                    set: { $0.fifteenMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.fiveMinutes + 1)...(model.settings.warningIntervals.thirtyMinutes - 1)
            )

            Stepper(
                "T-\(model.settings.warningIntervals.fiveMinutes) warning",
                value: warningBinding(
                    get: { $0.fiveMinutes },
                    set: { $0.fiveMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.twoMinutes + 1)...(model.settings.warningIntervals.fifteenMinutes - 1)
            )

            Stepper(
                "T-\(model.settings.warningIntervals.twoMinutes) warning",
                value: warningBinding(
                    get: { $0.twoMinutes },
                    set: { $0.twoMinutes = $1 }
                ),
                in: (model.settings.warningIntervals.oneMinute + 1)...(model.settings.warningIntervals.fiveMinutes - 1)
            )

            Stepper(
                "T-\(model.settings.warningIntervals.oneMinute) warning",
                value: warningBinding(
                    get: { $0.oneMinute },
                    set: { $0.oneMinute = $1 }
                ),
                in: 1...(model.settings.warningIntervals.twoMinutes - 1)
            )
        }
    }

    private var shutdownPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Shutdown")

            Toggle("Enable auto shutdown", isOn: $model.settings.autoShutdownEnabled)

            Stepper(
                "Shutdown delay: \(model.settings.autoShutdownDelayMinutes) min",
                value: $model.settings.autoShutdownDelayMinutes,
                in: 1...60
            )
        }
    }

    private var integrationsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Integrations",
                subtitle: "Optional modules for cloud sync, widgets, and external tooling."
            )

            integrationStatusRow(
                title: "WidgetKit",
                isEnabled: model.featureFlags.widgetKitEnabled
            )
            integrationStatusRow(
                title: "Cloud Sync",
                isEnabled: model.featureFlags.cloudSyncEnabled
            )
            integrationStatusRow(
                title: "MCP Server",
                isEnabled: model.featureFlags.mcpServerEnabled
            )
            integrationStatusRow(
                title: "Privileged Helper",
                isEnabled: model.featureFlags.privilegedHelperEnabled
            )
        }
    }

    private var devicesPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Devices",
                subtitle: "Current device and local override activity."
            )

            Text("Current device: \(Host.current().localizedName ?? Host.current().name ?? "Unknown")")
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.ink)

            Text("Override events logged locally: \(model.overrideEvents.count)")
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    private var advancedPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Advanced",
                subtitle: "Fine-grained controls for weekly reset timing and diagnostics."
            )

            Picker("Weekly reset day", selection: $model.settings.resetWeekday) {
                ForEach(Weekday.allCases) { weekday in
                    Text(weekday.shortName).tag(weekday)
                }
            }
            .pickerStyle(.segmented)

            Text("Reset day controls when extension and override budgets refresh.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    private func integrationStatusRow(title: String, isEnabled: Bool) -> some View {
        HStack {
            Text(title)
                .font(CurfewTypography.bodyEmphasis(14))
            Spacer()
            Text(isEnabled ? "Enabled" : "Disabled")
                .font(CurfewTypography.label(12))
                .foregroundStyle(isEnabled ? CurfewTheme.accent : CurfewTheme.mutedInk)
        }
    }

    private var setupPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Getting Started",
                subtitle: "Curfew is a full app with menu bar quick access."
            )

            if model.settings.hasCompletedInitialSetup {
                Text("Initial setup is complete.")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            } else {
                Button("Complete Setup and Enable Curfew") {
                    model.completeInitialSetup()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
            }

            HStack(spacing: 10) {
                Button("Show Getting Started") {
                    model.showGettingStarted()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                Button("Open Settings Window") {
                    model.openSettings()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
    }

    private func warningBinding(
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

private struct DayRuleRow: View {
    @EnvironmentObject private var model: CurfewAppModel
    let weekday: Weekday

    private var dayRule: DayRule {
        model.editableSchedule.rule(for: weekday)
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekday.shortName)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .frame(width: 48, alignment: .leading)

                Toggle("Day off", isOn: dayOffBinding())
                    .toggleStyle(.switch)
                    .font(CurfewTypography.body(13))

                Spacer()
            }

            HStack(spacing: 10) {
                Text("Lock")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .frame(width: 40, alignment: .leading)

                DatePicker(
                    "Lock",
                    selection: lockBinding(),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .disabled(dayRule.isDayOff)

                Text("->")
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.mutedInk)

                Text("Unlock")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)

                DatePicker(
                    "Unlock",
                    selection: unlockBinding(),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .disabled(dayRule.isDayOff)
            }
        }
        .padding(10)
        .background(CurfewTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? Date()
    }

    private func dateToMinutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

struct GettingStartedView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @State private var flow = FirstRunFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GettingStartedCopy.title)
                .font(CurfewTypography.display(30))

            Text(GettingStartedCopy.commitmentMessage)
                .font(CurfewTypography.body(18))
                .foregroundStyle(CurfewTheme.mutedInk)

            CurfewPanel {
                CurfewSectionTitle(
                    title: flow.currentStep.title,
                    subtitle: "Step \(flow.currentStep.rawValue + 1) of \(FirstRunStep.allCases.count)"
                )

                Text(flow.currentStep.message)
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(flow.currentStep.checklist, id: \.self) { line in
                        Label(line, systemImage: "checkmark.circle")
                    }
                }
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.ink)

                if flow.currentStep == .schedule {
                    Button("Open Schedule Settings") {
                        model.openSettings()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }

                if flow.currentStep == .extensionBudget {
                    Text("Current extension limit: \(model.settings.extensionWeeklyLimit) per week")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                    Text("Current override limit: \(model.settings.overrideWeeklyLimit) per week")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                if flow.currentStep == .permissions {
                    Text("You can review notifications and accessibility access in system settings at any time.")
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Back") {
                    flow.retreat()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
                .disabled(flow.isFirstStep)

                Button("Not now") {
                    model.dismissGettingStarted()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Spacer()

                if flow.isLastStep {
                    Button("Finish Setup") {
                        model.completeOnboardingFlow()
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") {
                        flow.advance()
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 470)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }
}
