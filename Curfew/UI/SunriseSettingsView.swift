import AppKit
import CurfewKit
import SwiftUI

/// The Sunrise pane: what Curfew shows and asks each morning, what runs when
/// the person finishes, and whether this Mac wakes itself for it.
///
/// Help text follows one rule: text about one control sits under that
/// control's label in the same row; text about a whole group is one footer
/// under it. The shared Settings rows have no secondary line yet, so rows
/// here use the system Form label (title, secondary line, trailing control).
struct SunriseSettingsView: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var shortcuts: [SunriseShortcut]?

    var body: some View {
        Group {
            previewSection
            questionsSection
            shortcutSection
            wakeSection
        }
        .task {
            shortcuts = await model.sunriseRuntime.shortcutRunner.list()
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            SunrisePreviewScene()
                .frame(width: 1440, height: 900)
                .scaleEffect(0.42, anchor: .topLeading)
                .frame(width: 1440 * 0.42, height: 900 * 0.42, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: CurfewRadius.control, style: .continuous))
                .opacity(model.isSunriseEnabled ? 1 : 0.45)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of Sunrise")
                .accessibilityIdentifier("sunrise-preview")
            Toggle(isOn: sunriseEnabled) {
                Text("Show Sunrise each morning")
                Text("When it's off, this Mac unlocks straight to the desktop.")
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("sunrise-enabled")
            LabeledContent {
                Button("Preview Sunrise") { SunrisePreviewWindow.show(model: model) }
                    .accessibilityIdentifier("sunrise-preview-button")
            } label: {
                Text("See it full size")
                Text("Nothing is saved and this Mac stays unlocked.")
            }
        }
    }

    // MARK: - In the morning

    private var questionsSection: some View {
        Section {
            ForEach(model.sunriseSteps) { step in
                SunriseQuestionRow(step: step)
            }
            .onMove { model.moveSunriseSteps(fromOffsets: $0, toOffset: $1) }
            Button("Add a question") {
                let id = model.addSunriseQuestion("")
                model.sunriseRuntime.editingStep = .question(id)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CurfewTheme.accent)
            .accessibilityIdentifier("sunrise-add-question")
        } header: {
            Text("In the morning")
        } footer: {
            Text("This Mac unlocks once you've answered the questions marked Must answer.")
                .font(CurfewTypography.body(12))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
        .disabled(!model.isSunriseEnabled)
    }

    // MARK: - After Sunrise

    private var shortcutSection: some View {
        Section {
            if let shortcuts, shortcuts.isEmpty, model.sunrisePreferences.shortcut == nil {
                LabeledContent {
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
                        )
                    }
                } label: {
                    Text("When you finish, run a Shortcut")
                    Text("You don't have any Shortcuts yet.")
                }
                .accessibilityIdentifier("sunrise-shortcut-none")
            } else {
                Picker(selection: shortcutSelection) {
                    Text("None").tag(String?.none)
                    ForEach(shortcutChoices, id: \.identifier) { shortcut in
                        Text(shortcut.name).tag(Optional(shortcut.identifier))
                    }
                } label: {
                    Text("When you finish, run a Shortcut")
                    if model.sunrisePreferences.shortcut != nil {
                        Text("Your answer to “What is today for?” is sent to the Shortcut.")
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("sunrise-shortcut")
            }
        }
        .disabled(!model.isSunriseEnabled)
    }

    // MARK: - Wake

    private var wakeSection: some View {
        let wake = model.restAppearance.sunriseWakeEnabled
        let hardware = model.sunriseRuntime.hardware
        let status = SunriseWakeStatusCopy.resolve(
            wakeEnabled: wake, curfewOn: model.isCurfewOnForSunrise,
            status: model.sunriseStatus, plan: model.sunriseWakePlan, now: model.currentTime
        )
        let shutdown = SunriseWakeStatusCopy.shutdownWarning(
            autoShutdownEnabled: model.settings.autoShutdownEnabled, wakeEnabled: wake
        )
        return Section {
            Toggle(isOn: wakeBinding) {
                Text("Wake this Mac for Sunrise")
                Text(wake ? "\(hardware.wakeRequirement) \(status.sentence)" : hardware
                    .wakeRequirement)
                if let shutdown {
                    Text(shutdown).foregroundStyle(CurfewTheme.warning)
                }
                if wake, status.fix == .protection {
                    Button("Open Protection settings") { model.settingsDestination = .general }
                        .buttonStyle(.link)
                }
                if shutdown != nil {
                    Button("Open Shutdown settings") { model.settingsDestination = .shutdown }
                        .buttonStyle(.link)
                }
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("sunrise-wake")
            SettingsValueRow(
                title: "Start brightening before unlock", value: leadBinding,
                range: 5 ... 60, step: 5, usesMinutes: true
            )
            .disabled(!wake)
            .accessibilityIdentifier("sunrise-lead")
            if hardware.hasBattery {
                Toggle("Allow on battery", isOn: batteryBinding)
                    .toggleStyle(.switch)
                    .disabled(!wake)
                    .accessibilityIdentifier("sunrise-battery")
            }
        } header: {
            Text("Wake")
        }
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
        let listed = shortcuts ?? []
        guard let picked = model.sunrisePreferences.shortcut,
              !listed.contains(where: { $0.identifier == picked.identifier })
        else { return listed }
        return [picked] + listed
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

/// One thing Sunrise shows or asks. At rest: its words, "Must answer" when it
/// holds the Mac, and one switch. Opened (click or Return): the question's
/// text where it can be edited, "Can be skipped", and "Delete question" for
/// the person's own questions. Reorders by dragging the handle that appears on
/// hover, or with Move up and Move down from the keyboard and VoiceOver.
private struct SunriseQuestionRow: View {
    @Environment(CurfewAppModel.self) private var model
    let step: SunriseStep
    @State private var hovering = false
    @FocusState private var fieldFocused: Bool

    private var isOpen: Bool {
        model.sunriseRuntime.editingStep == step.kind
    }

    private var title: String {
        let words = model.sunriseStepTitle(step.kind)
        return words.isEmpty ? "New question" : words
    }

    private var ownQuestionID: UUID? {
        if case .question(let id) = step.kind {
            return id
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            Toggle(isOn: shownBinding) {
                Text(title)
                if model.sunriseStepMustBeAnswered(step) {
                    Text("Must answer")
                }
            }
            .toggleStyle(.switch)
            .overlay(alignment: .leading) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .offset(x: -18)
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
            if isOpen {
                details
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleOpen() }
        .onHover { hovering = $0 }
        .focusable()
        .onKeyPress(.return) {
            toggleOpen()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isOpen ? "Close" : "Open") { toggleOpen() }
        .accessibilityAction(named: "Move up") { model.moveSunriseStep(step.kind, by: -1) }
        .accessibilityAction(named: "Move down") { model.moveSunriseStep(step.kind, by: 1) }
        .contextMenu {
            Button("Move up") { model.moveSunriseStep(step.kind, by: -1) }
            Button("Move down") { model.moveSunriseStep(step.kind, by: 1) }
        }
        .accessibilityIdentifier("sunrise-question")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            if let id = ownQuestionID {
                TextField("Your question", text: Binding(
                    get: { model.sunriseStepTitle(step.kind) },
                    set: { model.renameSunriseQuestion(id, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .task { fieldFocused = model.sunriseStepTitle(step.kind).isEmpty }
            }
            if step.kind != .lastNightNote {
                Toggle("Can be skipped", isOn: Binding(
                    get: { !step.isRequired },
                    set: { model.setSunriseStep(step.kind, canBeSkipped: $0) }
                ))
                .toggleStyle(.checkbox)
            }
            if let id = ownQuestionID {
                Button("Delete question", role: .destructive) { model.removeSunriseQuestion(id) }
                    .buttonStyle(.link)
            }
        }
        .padding(.leading, CurfewSpacing.large)
    }

    private var shownBinding: Binding<Bool> {
        Binding(get: { step.isEnabled }, set: { model.setSunriseStep(step.kind, shown: $0) })
    }

    private func toggleOpen() {
        model.sunriseRuntime.editingStep = isOpen ? nil : step.kind
    }
}
