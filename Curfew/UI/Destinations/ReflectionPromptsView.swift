import SwiftUI

/// The "Prompts" face of the Reflect destination — a first-class editor for the
/// questions you answer at the morning and evening gates. Promoted out of the
/// Settings window (where it was buried under a tab) into the workspace, beside
/// the reflections it shapes, reachable from ``JournalView``'s mode switcher.
///
/// Each prompt is its own card: the question on its own line with a tidy
/// overflow menu for reorder/remove, the answer-type controls on a second line
/// with room to breathe, and a quiet live preview — rather than the old single
/// cramped row. Edits round-trip through
/// ``CurfewAppModel/updateReflectionConfiguration(_:)`` so they persist
/// immediately, matching the rest of the app.
struct ReflectionPromptsView: View {
    /// Shared app state — prompts read/write through it.
    @EnvironmentObject private var model: CurfewAppModel

    /// Which prompt's text field should hold keyboard focus — set so a freshly
    /// added prompt is ready to type into.
    @FocusState private var focusedPromptID: UUID?

    /// Scrollable column of editor cards, matching the Schedule destination's
    /// padded `CurfewPanel` rhythm.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurfewSpacing.section) {
                gatesPanel
                promptsPanel(
                    for: .morning,
                    title: "Morning prompts",
                    subtitle: "Shown at the day's first session."
                )
                promptsPanel(
                    for: .evening,
                    title: "Evening prompts",
                    subtitle: "Shown on the lockout screen at sundown."
                )
                readInClaudePanel
                defaultsPanel
            }
            .padding(CurfewSpacing.xLarge)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Gates

    /// The two gate on/off toggles, with the explanatory copy *above* the
    /// controls so the panel reads top-down instead of bottom-heavy.
    private var gatesPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Reflection",
                subtitle: "Prompt yourself at the start and end of each day."
            )

            Text("The morning reflection greets you at the day's first session; "
                + "the evening one appears on the lockout screen. Both are always "
                + "skippable.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Morning intent (sunrise)", isOn: gateEnabledBinding(for: .morning))
            Toggle("Evening reflection (sundown)", isOn: gateEnabledBinding(for: .evening))
        }
    }

    // MARK: - Prompt editor

    private func promptsPanel(
        for gate: ReflectionGate,
        title: String,
        subtitle: String
    ) -> some View {
        CurfewPanel {
            CurfewSectionTitle(title: title, subtitle: subtitle)

            let prompts = model.reflectionConfiguration.prompts(for: gate)
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                promptCard(for: gate, prompt: prompt, index: index, total: prompts.count)
            }

            Button {
                addPrompt(for: gate)
            } label: {
                Label("Add prompt", systemImage: "plus.circle")
            }
            .buttonStyle(CurfewLinkButtonStyle())
            .padding(.top, CurfewSpacing.xSmall)
        }
    }

    /// One prompt rendered as a self-contained card on the panel's surface, so
    /// each question reads as a discrete unit with its own controls.
    private func promptCard(
        for gate: ReflectionGate,
        prompt: ReflectionPrompt,
        index: Int,
        total: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            HStack(spacing: CurfewSpacing.small) {
                TextField("Question", text: promptTextBinding(for: gate, promptID: prompt.id))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedPromptID, equals: prompt.id)

                promptMenu(for: gate, index: index, total: total)
            }

            HStack(spacing: CurfewSpacing.medium) {
                answerTypePicker(for: gate, prompt: prompt)
                if prompt.kind == .rating {
                    Stepper(
                        "Scale 1–\(prompt.ratingMax)",
                        value: promptScaleBinding(for: gate, promptID: prompt.id),
                        in: 2 ... 10
                    )
                    .fixedSize()
                    .accessibilityLabel("Rating scale, 1 to \(prompt.ratingMax)")
                }
                Spacer(minLength: 0)
            }

            if prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Add a question, or remove this row.", systemImage: "exclamationmark.circle")
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.warning)
            }

            promptPreview(for: prompt)
        }
        .padding(CurfewSpacing.medium)
        .background(
            CurfewTheme.surfaceMuted,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CurfewTheme.border, lineWidth: 1)
        )
    }

    /// Reorder / remove collapsed into a single overflow menu, so the question
    /// field gets the row's width instead of fighting three inline icon buttons.
    private func promptMenu(for gate: ReflectionGate, index: Int, total: Int) -> some View {
        Menu {
            Button {
                movePrompt(for: gate, from: index, to: index - 1)
            } label: {
                Label("Move Up", systemImage: "chevron.up")
            }
            .disabled(index == 0)

            Button {
                movePrompt(for: gate, from: index, to: index + 1)
            } label: {
                Label("Move Down", systemImage: "chevron.down")
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
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Prompt options")
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
        .frame(maxWidth: 260)
    }

    /// A compact, non-interactive preview of how the prompt's answer control
    /// renders, so the user sees what they're building. Chips use the raised
    /// `surface` so they read against the muted card.
    private func promptPreview(for prompt: ReflectionPrompt) -> some View {
        HStack(spacing: CurfewSpacing.small) {
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
                    .background(CurfewTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            case .rating:
                HStack(spacing: 5) {
                    ForEach(1 ... max(2, prompt.ratingMax), id: \.self) { value in
                        Text("\(value)")
                            .font(CurfewTypography.body(11))
                            .frame(width: 20, height: 20)
                            .background(CurfewTheme.surface, in: Circle())
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

    // MARK: - Connect / defaults

    /// Points the user at the Integrations settings to connect an assistant that
    /// can read their reflections. Only shown when this build ships the MCP
    /// control plane.
    @ViewBuilder
    private var readInClaudePanel: some View {
        if model.featureFlags.mcpServerEnabled {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Read your reflections in Claude",
                    subtitle: "Connect an AI assistant to read your morning and evening "
                        + "reflections — read-only, and they never leave this Mac."
                )
                Button("Open Integrations Settings") {
                    model.openSettings()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
    }

    private var defaultsPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(title: "Defaults")

            Label(
                "AI-suggested prompts are coming — generated on-device from your "
                    + "day's context.",
                systemImage: "sparkles"
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)

            Button("Restore default prompts") {
                model.updateReflectionConfiguration(.default)
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
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
