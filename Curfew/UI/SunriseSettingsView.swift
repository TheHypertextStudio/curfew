import CurfewKit
import SwiftUI

/// The Sunrise pane in Settings: whether Sunrise appears, its steps, the
/// Shortcut that runs after it, and whether this Mac wakes itself for it.
struct SunriseSettingsView: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var shortcuts: [SunriseShortcut] = []

    var body: some View {
        Group {
            Section {
                SettingsToggleRow(title: "Show Sunrise at unlock", isOn: sunriseEnabled)
                    .accessibilityIdentifier("sunrise-enabled")
                Text("This Mac stays on Sunrise until you name what today is for.")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Section {
                ForEach(Array(model.sunriseSteps.enumerated()), id: \.element.id) { index, step in
                    SunriseStepRow(step: step, index: index, count: model.sunriseSteps.count)
                }
                .onMove { source, destination in
                    var steps = model.sunriseSteps
                    steps.move(fromOffsets: source, toOffset: destination)
                    model.updateSunriseSteps(steps)
                }
                Button {
                    model.addSunriseQuestion("")
                } label: {
                    Label("Add a question", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("sunrise-add-question")
            } header: {
                Text("Steps")
            } footer: {
                Text("Sunrise asks these in order. A required step can't be skipped.")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            .disabled(!model.isSunriseEnabled)
            Section {
                Picker("Then run a Shortcut", selection: shortcutSelection) {
                    Text("None").tag(String?.none)
                    ForEach(shortcutChoices, id: \.identifier) { shortcut in
                        Text(shortcut.name).tag(Optional(shortcut.identifier))
                    }
                }
                .pickerStyle(.menu)
                .font(CurfewTypography.bodyEmphasis(13))
                .accessibilityIdentifier("sunrise-shortcut")
                Text("Curfew passes the one thing to it as text.")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            } header: {
                Text("After Sunrise")
            }
            .disabled(!model.isSunriseEnabled)
            wakeSection
        }
        .task {
            shortcuts = await model.sunriseRuntime.shortcutRunner.list()
        }
    }

    private var wakeSection: some View {
        let wake = model.restAppearance.sunriseWakeEnabled
        let status = SunriseWakeStatusCopy.resolve(
            wakeEnabled: wake, curfewOn: model.isCurfewOnForSunrise,
            status: model.sunriseStatus, plan: model.sunriseWakePlan,
            now: model.currentTime
        )
        let shutdown = SunriseWakeStatusCopy.shutdownWarning(
            autoShutdownEnabled: model.settings.autoShutdownEnabled, wakeEnabled: wake
        )
        return Section {
            VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                SettingsToggleRow(title: "Wake this Mac for Sunrise", isOn: wakeBinding)
                    .accessibilityIdentifier("sunrise-wake")
                Text("Needs the Curfew helper, power, and an open lid.")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Group {
                SettingsValueRow(
                    title: "Start brightening before unlock", value: leadBinding,
                    range: 5 ... 60, step: 5, usesMinutes: true
                )
                .accessibilityIdentifier("sunrise-lead")
                SettingsToggleRow(title: "Allow on battery", isOn: batteryBinding)
                    .opacity(wake ? 1 : 0.5)
                    .accessibilityIdentifier("sunrise-battery")
            }
            .disabled(!wake)
            statusRow(status)
            if let shutdown {
                statusLine(
                    shutdown, symbol: "power", tint: CurfewTheme.warning,
                    action: "Open Shutdown settings"
                ) {
                    model.settingsDestination = .shutdown
                }
                .accessibilityIdentifier("sunrise-shutdown-warning")
            }
        } header: {
            Text("Wake")
        }
    }

    private func statusRow(_ status: SunriseWakeStatusCopy) -> some View {
        let blocked = status.fix != nil || model.sunriseStatus == .batteryExcluded
        return statusLine(
            status.sentence,
            symbol: blocked ? "exclamationmark.triangle" : HorizonSymbol.sunrise.systemName,
            tint: blocked ? CurfewTheme.warning : CurfewTheme.accent,
            action: status.fix == .protection ? "Open Protection settings" : nil
        ) {
            model.settingsDestination = .general
        }
        .accessibilityIdentifier("sunrise-status")
    }

    private func statusLine(
        _ text: String, symbol: String, tint: Color, action: String?,
        perform: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CurfewSpacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                Text(text)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action, action: perform)
                        .buttonStyle(.plain)
                        .font(CurfewTypography.bodyEmphasis(12))
                        .foregroundStyle(CurfewTheme.accent)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bindings

    private var sunriseEnabled: Binding<Bool> {
        Binding(get: { model.isSunriseEnabled }, set: { model.setSunriseEnabled($0) })
    }

    private var wakeBinding: Binding<Bool> {
        Binding(
            get: { model.restAppearance.sunriseWakeEnabled },
            set: { model.updateSunriseWake(enabled: $0) }
        )
    }

    private var leadBinding: Binding<Int> {
        Binding(
            get: { model.restAppearance.sunriseLeadMinutes },
            set: { model.updateSunriseWake(leadMinutes: $0) }
        )
    }

    private var batteryBinding: Binding<Bool> {
        Binding(
            get: { model.restAppearance.sunriseOnBatteryEnabled },
            set: { model.updateSunriseWake(onBattery: $0) }
        )
    }

    /// The listed shortcuts, plus the picked one if it is not listed (the
    /// list may still be loading, or the Shortcut was renamed).
    private var shortcutChoices: [SunriseShortcut] {
        guard let picked = model.sunrisePreferences.shortcut,
              !shortcuts.contains(where: { $0.identifier == picked.identifier })
        else { return shortcuts }
        return [picked] + shortcuts
    }

    private var shortcutSelection: Binding<String?> {
        Binding(
            get: { model.sunrisePreferences.shortcut?.identifier },
            set: { identifier in
                model.setSunriseShortcut(shortcutChoices.first { $0.identifier == identifier })
            }
        )
    }
}

/// One step: what it shows, on or off, required or skippable, and a menu to
/// move or remove it, so reordering works from the keyboard and VoiceOver too.
private struct SunriseStepRow: View {
    @Environment(CurfewAppModel.self) private var model
    let step: SunriseStep
    let index: Int
    let count: Int

    private var prompt: ReflectionPrompt? {
        guard case .question(let id) = step.kind else { return nil }
        return model.reflectionConfiguration.morningPrompts.first { $0.id == id }
    }

    private var title: String {
        switch step.kind {
        case .lastNightNote: "Last night's note"
        case .oneThing: SunriseVoice.question
        case .readiness:
            model.reflectionConfiguration.morningPrompts
                .first { $0.id == JournalPromptIDs.readiness }?.text ?? SunriseVoice.readiness
        case .question: prompt?.text ?? ""
        }
    }

    private var symbol: String {
        switch step.kind {
        case .lastNightNote: HorizonSymbol.lastNight.systemName
        case .oneThing: HorizonSymbol.oneThing.systemName
        case .readiness: "gauge.with.needle"
        case .question: "text.bubble"
        }
    }

    var body: some View {
        HStack(spacing: CurfewSpacing.medium) {
            Image(systemName: symbol)
                .foregroundStyle(step.isEnabled ? CurfewTheme.accent : CurfewTheme.mutedInk)
                .frame(width: 20)
                .accessibilityHidden(true)
            titleView
            Spacer(minLength: CurfewSpacing.small)
            if step.kind != .lastNightNote {
                Picker("", selection: requiredBinding) {
                    Text("Required").tag(true)
                    Text("Skippable").tag(false)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(!step.isEnabled)
                .accessibilityLabel("\(title), required or skippable")
            }
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Ask \(title)")
            Menu {
                Button("Move up") { move(by: -1) }.disabled(index == 0)
                Button("Move down") { move(by: 1) }.disabled(index == count - 1)
                if let prompt {
                    Divider()
                    Button("Remove question", role: .destructive) {
                        model.removeSunriseQuestion(prompt.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(title)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var titleView: some View {
        if let prompt {
            TextField("Your question", text: Binding(
                get: { prompt.text },
                set: { model.renameSunriseQuestion(prompt.id, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(CurfewTypography.body(13))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CurfewTypography.bodyEmphasis(13))
                if step.kind == .lastNightNote {
                    Text("What you left for next time, shown above the question.")
                        .font(CurfewTypography.body(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { step.isEnabled }, set: { value in update { $0.isEnabled = value } })
    }

    private var requiredBinding: Binding<Bool> {
        Binding(get: { step.isRequired }, set: { value in update { $0.isRequired = value } })
    }

    private func update(_ change: (inout SunriseStep) -> Void) {
        var steps = model.sunriseSteps
        guard let position = steps.firstIndex(where: { $0.kind == step.kind }) else { return }
        change(&steps[position])
        model.updateSunriseSteps(steps)
    }

    private func move(by offset: Int) {
        var steps = model.sunriseSteps
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
        model.updateSunriseSteps(steps)
    }
}
