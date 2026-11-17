import CurfewKit
import SwiftUI

/// The questions editor for Sunrise and curfew, reachable from ``JournalView``.
/// Laid out with the Settings rows: each group's explanation is its footer,
/// each question is one row (the question, its answer type and a preview of
/// the answer), and a question's own problem shows under it in that row.
/// Edits round-trip through ``CurfewAppModel/updateReflectionConfiguration(_:)``.
struct ReflectionPromptsView: View {
    /// Shared app state; prompts read and write through it.
    @Environment(CurfewAppModel.self) private var model

    /// Which prompt's text field should hold keyboard focus, set so a freshly
    /// added prompt is ready to type into.
    @FocusState private var focusedPromptID: UUID?

    /// Restoring defaults replaces every custom question, so it asks first.
    @State private var confirmingRestoreDefaults = false

    var body: some View {
        Form {
            SettingsGroup(
                ReflectionPromptsCopy.gatesTitle,
                footer: ReflectionPromptsCopy.gatesSubtitle
            ) {
                SettingsToggleRow(
                    title: ReflectionPromptsCopy.askAtSunrise,
                    isOn: gateEnabledBinding(for: .morning)
                )
                SettingsToggleRow(
                    title: ReflectionPromptsCopy.askAtCurfew,
                    isOn: gateEnabledBinding(for: .evening)
                )
            }
            promptsGroup(
                for: .morning,
                title: ReflectionPromptsCopy.sunriseTitle,
                footer: ReflectionPromptsCopy.sunriseSubtitle
            )
            promptsGroup(
                for: .evening,
                title: ReflectionPromptsCopy.curfewTitle,
                footer: ReflectionPromptsCopy.curfewSubtitle
            )
            if model.featureFlags.mcpServerEnabled {
                SettingsGroup {
                    SettingsActionRow(
                        title: ReflectionPromptsCopy.claudeTitle,
                        detail: ReflectionPromptsCopy.claudeDetail,
                        actionTitle: ReflectionPromptsCopy.claudeButton
                    ) {
                        model.settingsDestination = .integrations
                        model.openSettings()
                    }
                }
            }
            SettingsGroup {
                SettingsActionRow(
                    title: ReflectionPromptsCopy.defaultsTitle,
                    detail: ReflectionPromptsCopy.defaultsSubtitle,
                    actionTitle: ReflectionPromptsCopy.restoreButton
                ) {
                    confirmingRestoreDefaults = true
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(CurfewTheme.canvas)
        .confirmationDialog(
            ReflectionPromptsCopy.restoreTitle,
            isPresented: $confirmingRestoreDefaults
        ) {
            Button(ReflectionPromptsCopy.restoreConfirm, role: .destructive) {
                model.updateReflectionConfiguration(.default)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ReflectionPromptsCopy.restoreMessage)
        }
    }

    // MARK: - Prompt editor

    private func promptsGroup(
        for gate: ReflectionGate,
        title: String,
        footer: String
    ) -> some View {
        let prompts = model.reflectionConfiguration.prompts(for: gate)
        return SettingsGroup(title, footer: footer) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                promptRow(for: gate, prompt: prompt, index: index, total: prompts.count)
            }
            Button(ReflectionPromptsCopy.addQuestion) {
                addPrompt(for: gate)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CurfewTheme.accent)
        }
    }

    /// One question as one row: the question and its options on the first
    /// line, how it is answered under it, and its problem, if any, last.
    private func promptRow(
        for gate: ReflectionGate,
        prompt: ReflectionPrompt,
        index: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            HStack(spacing: CurfewSpacing.small) {
                TextField("Question", text: promptTextBinding(for: gate, promptID: prompt.id))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedPromptID, equals: prompt.id)

                promptMenu(for: gate, index: index, total: total)
            }

            HStack(spacing: CurfewSpacing.medium) {
                answerTypePicker(for: gate, prompt: prompt)
                if prompt.kind == .rating {
                    HStack(spacing: CurfewSpacing.xSmall) {
                        Text("Scale of \(prompt.ratingMax)")
                            .font(CurfewTypography.body(12))
                            .foregroundStyle(CurfewTheme.mutedInk)
                            .accessibilityHidden(true)
                        Stepper(
                            "Scale of \(prompt.ratingMax)",
                            value: promptScaleBinding(for: gate, promptID: prompt.id),
                            in: 2 ... 10
                        )
                        .labelsHidden()
                        .accessibilityLabel("Rating scale, 1 to \(prompt.ratingMax)")
                    }
                    .fixedSize()
                }
                Spacer(minLength: CurfewSpacing.small)
                promptPreview(for: prompt)
            }

            if prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(ReflectionPromptsCopy.emptyQuestion)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.warning)
            }
        }
        .padding(.vertical, 2)
    }

    /// Reorder / remove collapsed into a single overflow menu, so the question
    /// field gets the row's width instead of fighting three inline icon buttons.
    private func promptMenu(for gate: ReflectionGate, index: Int, total: Int) -> some View {
        Menu {
            Button {
                movePrompt(for: gate, from: index, to: index - 1)
            } label: {
                Label("Move up", systemImage: "chevron.up")
            }
            .disabled(index == 0)

            Button {
                movePrompt(for: gate, from: index, to: index + 1)
            } label: {
                Label("Move down", systemImage: "chevron.down")
            }
            .disabled(index == total - 1)

            Divider()

            Button(role: .destructive) {
                removePrompt(for: gate, at: index)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
        .menuStyle(.borderlessButton)
        .help("Move or remove this question")
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Question options")
    }

    /// The segmented text / rating / mood picker.
    private func answerTypePicker(
        for gate: ReflectionGate,
        prompt: ReflectionPrompt
    ) -> some View {
        Picker("Answer type", selection: promptKindBinding(for: gate, promptID: prompt.id)) {
            Label("Text", systemImage: "text.alignleft").tag(ReflectionPromptKind.text)
            Label("Rating", systemImage: "number").tag(ReflectionPromptKind.rating)
            Label("Mood", systemImage: "face.smiling").tag(ReflectionPromptKind.mood)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    /// A compact, non-interactive preview of how the prompt's answer control
    /// renders, so the person sees what they're building, at the row's end.
    private func promptPreview(for prompt: ReflectionPrompt) -> some View {
        HStack(spacing: CurfewSpacing.small) {
            switch prompt.kind {
            case .text:
                Text("A short written answer")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CurfewTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 6))
            case .rating:
                HStack(spacing: 5) {
                    ForEach(1 ... max(2, prompt.ratingMax), id: \.self) { value in
                        Text("\(value)")
                            .font(CurfewTypography.body(11))
                            .frame(width: 20, height: 20)
                            .background(CurfewTheme.surfaceMuted, in: Circle())
                            .foregroundStyle(CurfewTheme.mutedInk)
                    }
                }
            case .mood:
                HStack(spacing: 4) {
                    ForEach(ReflectionMood.allCases, id: \.self) { mood in
                        Text(ReflectionFormView.moodGlyph(mood))
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answered with \(prompt.kind.previewName)")
    }
}

private extension ReflectionPromptKind {
    /// What the answer looks like, for the preview's spoken label.
    var previewName: String {
        switch self {
        case .text: "a short written answer"
        case .rating: "a rating"
        case .mood: "a mood"
        }
    }
}

// MARK: - Bindings & mutations

/// Prompt-array bindings and mutations, split into an extension so the view's
/// declaration stays focused on layout.
extension ReflectionPromptsView {
    private func gateEnabledBinding(for gate: ReflectionGate) -> Binding<Bool> {
        Binding(
            get: { model.reflectionConfiguration.isEnabled(gate) },
            set: { newValue in
                var config = model.reflectionConfiguration
                switch gate {
                case .morning: config.morningEnabled = newValue
                case .evening: config.eveningEnabled = newValue
                }
                model.updateReflectionConfiguration(config)
            }
        )
    }

    private func promptTextBinding(
        for gate: ReflectionGate,
        promptID: UUID
    ) -> Binding<String> {
        Binding(
            get: {
                model.reflectionConfiguration.prompts(for: gate)
                    .first { $0.id == promptID }?.text ?? ""
            },
            set: { newValue in
                mutatePrompts(for: gate) { prompts in
                    guard let index = prompts.firstIndex(where: { $0.id == promptID }) else {
                        return
                    }
                    prompts[index].text = newValue
                }
            }
        )
    }

    private func promptKindBinding(
        for gate: ReflectionGate,
        promptID: UUID
    ) -> Binding<ReflectionPromptKind> {
        Binding(
            get: {
                model.reflectionConfiguration.prompts(for: gate)
                    .first { $0.id == promptID }?.kind ?? .text
            },
            set: { newValue in
                mutatePrompts(for: gate) { prompts in
                    guard let index = prompts.firstIndex(where: { $0.id == promptID }) else {
                        return
                    }
                    prompts[index].kind = newValue
                }
            }
        )
    }

    private func promptScaleBinding(
        for gate: ReflectionGate,
        promptID: UUID
    ) -> Binding<Int> {
        Binding(
            get: {
                model.reflectionConfiguration.prompts(for: gate)
                    .first { $0.id == promptID }?.ratingMax ?? 5
            },
            set: { newValue in
                mutatePrompts(for: gate) { prompts in
                    guard let index = prompts.firstIndex(where: { $0.id == promptID }) else {
                        return
                    }
                    prompts[index].ratingMax = newValue
                }
            }
        )
    }

    private func addPrompt(for gate: ReflectionGate) {
        let new = ReflectionPrompt(text: "", kind: .text)
        mutatePrompts(for: gate) { prompts in
            prompts.append(new)
        }
        focusedPromptID = new.id
    }

    private func removePrompt(for gate: ReflectionGate, at index: Int) {
        mutatePrompts(for: gate) { prompts in
            guard prompts.indices.contains(index) else { return }
            prompts.remove(at: index)
        }
    }

    private func movePrompt(for gate: ReflectionGate, from: Int, to destination: Int) {
        mutatePrompts(for: gate) { prompts in
            guard prompts.indices.contains(from), destination >= 0, destination < prompts.count
            else { return }
            let prompt = prompts.remove(at: from)
            prompts.insert(prompt, at: destination)
        }
    }

    /// Applies `transform` to `gate`'s prompt array and persists the result.
    private func mutatePrompts(
        for gate: ReflectionGate,
        _ transform: (inout [ReflectionPrompt]) -> Void
    ) {
        var config = model.reflectionConfiguration
        switch gate {
        case .morning: transform(&config.morningPrompts)
        case .evening: transform(&config.eveningPrompts)
        }
        model.updateReflectionConfiguration(config)
    }
}
