import SwiftUI

/// Settings panel for the reflection gates: per-gate enable toggles and a
/// full editor for each gate's prompt set — reorder, per-prompt answer type,
/// configurable rating scale, a live preview, and inline validation. Edits
/// round-trip through ``CurfewAppModel/updateReflectionConfiguration(_:)`` so
/// they persist immediately, matching the rest of Settings.
extension SettingsView {
    var reflectionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Reflection",
                    subtitle: "Prompt yourself at the start and end of each day."
                )

                Toggle("Morning intent (sunrise)", isOn: gateEnabledBinding(for: .morning))
                Toggle("Evening reflection (sundown)", isOn: gateEnabledBinding(for: .evening))

                Text("The evening reflection appears on the lockout screen; the "
                    + "morning one greets you at the day's first session. Both are "
                    + "always skippable.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            promptsPanel(for: .morning, title: "Morning prompts")
            promptsPanel(for: .evening, title: "Evening prompts")

            readInClaudePanel

            CurfewPanel {
                CurfewSectionTitle(title: "Defaults")
                Button("Restore default prompts") {
                    model.updateReflectionConfiguration(.default)
                }

                Label(
                    "AI-suggested prompts are coming — generated on-device from your "
                        + "day's context.",
                    systemImage: "sparkles"
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    /// Points the user at the Integrations tab to connect an assistant that can
    /// read their reflections. Only shown when this build ships the MCP control
    /// plane (otherwise the Integrations MCP section is hidden too).
    @ViewBuilder
    private var readInClaudePanel: some View {
        if model.featureFlags.mcpServerEnabled {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Read your reflections in Claude",
                    subtitle: "Your morning and evening reflections are available to AI "
                        + "assistants you connect — read-only, and they never leave this Mac."
                )
                Button("Set up in Integrations") {
                    selection = .integrations
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
    }

    private func promptsPanel(for gate: ReflectionGate, title: String) -> some View {
        CurfewPanel {
            CurfewSectionTitle(title: title)

            let prompts = model.reflectionConfiguration.prompts(for: gate)
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                promptRow(for: gate, prompt: prompt, index: index, total: prompts.count)
                if index < prompts.count - 1 {
                    Divider().padding(.vertical, 2)
                }
            }

            Button {
                addPrompt(for: gate)
            } label: {
                Label("Add prompt", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }

    private func promptRow(
        for gate: ReflectionGate,
        prompt: ReflectionPrompt,
        index: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Question", text: promptTextBinding(for: gate, promptID: prompt.id))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedPromptID, equals: prompt.id)

                Button {
                    movePrompt(for: gate, from: index, to: index - 1)
                } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move prompt up")

                Button {
                    movePrompt(for: gate, from: index, to: index + 1)
                } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index == total - 1)
                    .accessibilityLabel("Move prompt down")

                Button {
                    removePrompt(for: gate, at: index)
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove prompt")
            }

            answerTypeControls(for: gate, prompt: prompt)

            if prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Add a question, or remove this row.", systemImage: "exclamationmark.circle")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.warning)
            }

            promptPreview(for: prompt)
        }
        .padding(.vertical, 4)
    }

    /// The segmented answer-type picker plus, for rating prompts, the 1–N scale
    /// stepper. Split out so ``promptRow(for:prompt:index:total:)`` stays terse.
    private func answerTypeControls(
        for gate: ReflectionGate,
        prompt: ReflectionPrompt
    ) -> some View {
        HStack(spacing: 12) {
            Picker("Answer type", selection: promptKindBinding(for: gate, promptID: prompt.id)) {
                Label("Text", systemImage: "text.alignleft").tag(ReflectionPromptKind.text)
                Label("Rating", systemImage: "number").tag(ReflectionPromptKind.rating)
                Label("Mood", systemImage: "face.smiling").tag(ReflectionPromptKind.mood)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            if prompt.kind == .rating {
                Stepper(
                    "Scale 1–\(prompt.ratingMax)",
                    value: promptScaleBinding(for: gate, promptID: prompt.id),
                    in: 2 ... 10
                )
                .fixedSize()
                .accessibilityLabel("Rating scale, 1 to \(prompt.ratingMax)")
            }
        }
    }

    /// A compact, non-interactive preview of how the prompt's answer control
    /// will render, so the user sees what they're building (including multiple
    /// rating questions). Light-themed to sit in Settings.
    private func promptPreview(for prompt: ReflectionPrompt) -> some View {
        HStack(spacing: 8) {
            Text("Preview")
                .font(CurfewTypography.label(11))
                .foregroundStyle(CurfewTheme.mutedInk)
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
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bindings & mutations

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
