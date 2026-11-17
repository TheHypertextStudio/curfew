import CurfewKit
import SwiftUI

/// Shared input form for a reflection gate. Renders a configured prompt set as
/// the right control per kind (prose / 1–N rating / mood pick), collects the
/// answers locally, and hands a built `[ReflectionAnswer]` back on submit.
///
/// Used by the in-lockout ``EveningReflectionCard``, which supply their own surrounding
/// chrome (background, headline). Styled for a dark dusk/dawn backdrop:
/// white-on-translucent, rounded type, matching the lockout screen. All sizes
/// scale with Dynamic Type via ``ScaledMetric``.
struct ReflectionFormView: View {
    /// The prompts to render, in order.
    @Bindable var draft: ReflectionDraft

    private var prompts: [ReflectionPrompt] {
        draft.prompts
    }

    private var values: [UUID: ReflectionValue] {
        get { draft.values }
        nonmutating set { draft.values = newValue }
    }

    /// Label for the primary (submit) button, e.g. "Start the day" or
    /// "Save and close".
    let submitLabel: String

    /// Label for the lenient dismissal.
    var skipLabel = "Skip"

    /// Whether non-text panels switch to solid fills for Reduce Transparency.
    let usesSolidPanels: Bool

    /// Called with the built answers when the user submits. Only prompts the
    /// user actually answered are included.
    let onSubmit: ([ReflectionAnswer]) -> Void

    /// The empty state's two lines, when no questions are configured.
    var emptyTitle = "No questions here yet."
    var emptyDetail = "Add some in Journal."

    /// True when the surrounding surface collected an answer of its own (the
    /// close-out's yes or no), so saving is allowed without a prompt answer.
    var extraAnswerGiven = false

    /// Called when the user skips — the lenient dismissal path.
    let onSkip: () -> Void

    init(
        draft: ReflectionDraft, submitLabel: String, skipLabel: String = "Skip",
        usesSolidPanels: Bool, emptyTitle: String = "No questions here yet.",
        emptyDetail: String = "Add some in Journal.", extraAnswerGiven: Bool = false,
        onSubmit: @escaping ([ReflectionAnswer]) -> Void, onSkip: @escaping () -> Void
    ) {
        self.draft = draft
        self.submitLabel = submitLabel
        self.skipLabel = skipLabel
        self.usesSolidPanels = usesSolidPanels
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.extraAnswerGiven = extraAnswerGiven
        self.onSubmit = onSubmit
        self.onSkip = onSkip
    }

    // Dynamic Type — base sizes that scale with the user's text-size setting.
    @FocusState private var focusedPrompt: UUID?
    @ScaledMetric(relativeTo: .body) private var promptFontSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var editorFontSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var ratingFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var ratingButtonSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var moodGlyphSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var moodLabelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var moodButtonWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var moodButtonHeight: CGFloat = 60

    /// Prompts with real question text. A blank prompt — added in the editor
    /// via "Add prompt" and then abandoned before typing a question, or left
    /// blank after editing — has nothing for the user to answer, so it's
    /// filtered here rather than rendered as an unlabeled, unanswerable
    /// control at the live gate. The editor itself still shows every prompt,
    /// blank or not, so the user can find and fill in (or delete) it.
    private var visiblePrompts: [ReflectionPrompt] {
        prompts.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.large) {
            if visiblePrompts.isEmpty {
                emptyPromptsNotice
            } else {
                ForEach(visiblePrompts) { prompt in
                    VStack(alignment: .leading, spacing: CurfewSpacing.small) {
                        titleText(prompt.text)
                        control(for: prompt)
                    }
                }

                actions(canSubmit: !builtAnswers().isEmpty || extraAnswerGiven)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// Shown instead of a dead form when every prompt for this gate has been
    /// removed (in Reflection settings) — otherwise the user sees a
    /// permanently-disabled submit button with no explanation for why. A real
    /// "Continue" (not a de-emphasized "Skip") since there is genuinely
    /// nothing to answer, not something they're opting out of.
    private var emptyPromptsNotice: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.large) {
            VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                titleText(emptyTitle)
                Text(emptyDetail)
                    .font(.system(size: editorFontSize))
                    .foregroundStyle(SundownPalette.supportingText)
            }
            if extraAnswerGiven {
                actions(canSubmit: true)
            } else {
                Button(submitLabel, action: onSkip)
                    .buttonStyle(.horizonGlassProminent)
            }
        }
    }

    /// The primary action in the foundation's prominent glass, and the quiet skip.
    private func actions(canSubmit: Bool) -> some View {
        HStack(spacing: CurfewSpacing.large) {
            Button(submitLabel) { onSubmit(builtAnswers()) }
                .buttonStyle(.horizonGlassProminent)
                .disabled(!canSubmit)
            Button(skipLabel, action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(SundownPalette.supportingText)
        }
        .padding(.top, CurfewSpacing.xSmall)
    }

    /// Shared style for a prompt's question text and the empty-state
    /// headline — the two "this is the main thing to read" lines on this
    /// form — so they can't drift from each other one at a time.
    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: promptFontSize, weight: .medium, design: .rounded))
            .foregroundStyle(SundownPalette.warmWhite)
    }

    /// Builds answers for every prompt the user meaningfully answered:
    /// non-empty text, a rating ≥ 1, or a selected mood. Untouched prompts are
    /// omitted so the stored reflection never carries empty rows.
    private func builtAnswers() -> [ReflectionAnswer] {
        visiblePrompts.compactMap { prompt -> ReflectionAnswer? in
            guard let value = values[prompt.id], isMeaningful(value) else { return nil }
            return ReflectionAnswer(
                promptID: prompt.id,
                promptTextSnapshot: prompt.text,
                value: value
            )
        }
    }

    private func isMeaningful(_ value: ReflectionValue) -> Bool {
        switch value {
        case .text(let string):
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .rating(let rating, _):
            rating >= 1
        case .mood:
            true
        }
    }

    @ViewBuilder
    private func control(for prompt: ReflectionPrompt) -> some View {
        switch prompt.kind {
        case .text:
            let focused = focusedPrompt == prompt.id
            TextEditor(text: textBinding(for: prompt.id))
                .foregroundStyle(SundownPalette.warmWhite)
                .font(.system(size: editorFontSize))
                .scrollContentBackground(.hidden)
                .focused($focusedPrompt, equals: prompt.id)
                .frame(height: 56)
                .padding(.horizontal, CurfewSpacing.small)
                .padding(.vertical, CurfewSpacing.small)
                .background(SceneField.fill, in: SceneField.shape)
                .overlay {
                    SceneField.shape.strokeBorder(
                        SundownPalette.warmWhite.opacity(focused ? 0.6 : 0.16),
                        lineWidth: focused ? 1.5 : 1
                    )
                }
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityLabel(prompt.text)
                .accessibilityIdentifier("reflection-answer")
        case .rating:
            ratingControl(for: prompt.id, scale: prompt.ratingMax)
        case .mood:
            moodControl(for: prompt.id)
        }
    }

    // MARK: - Rating

    /// One segmented control: a quiet track with the chosen number filled.
    private func ratingControl(for id: UUID, scale: Int) -> some View {
        let current = currentRating(for: id)
        return HStack(spacing: CurfewSpacing.xSmall) {
            ForEach(1 ... max(2, scale), id: \.self) { value in
                Button("\(value)") {
                    values[id] = .rating(value: value, scale: scale)
                }
                .buttonStyle(SceneChoiceButtonStyle(
                    chosen: value == current, minWidth: ratingButtonSize
                ))
                .accessibilityLabel("\(value) out of \(scale)")
                .accessibilityAddTraits(value == current ? [.isSelected] : [])
            }
        }
        .padding(CurfewSpacing.xSmall)
        .background(SceneField.fill, in: SceneField.shape)
        .overlay { SceneField.shape.strokeBorder(
            SundownPalette.warmWhite.opacity(0.16),
            lineWidth: 1
        ) }
        .fixedSize()
    }

    private func currentRating(for id: UUID) -> Int {
        if case .rating(let value, _) = values[id] {
            return value
        }
        return 0
    }

    // MARK: - Mood

    private func moodControl(for id: UUID) -> some View {
        let current = currentMood(for: id)
        return HStack(spacing: CurfewSpacing.xSmall) {
            ForEach(ReflectionMood.allCases, id: \.self) { mood in
                Button {
                    values[id] = .mood(mood)
                } label: {
                    VStack(spacing: CurfewSpacing.xSmall) {
                        Text(Self.moodGlyph(mood))
                            .font(.system(size: moodGlyphSize))
                        Text(Self.moodLabel(mood))
                            .font(.system(size: moodLabelSize, weight: .medium))
                    }
                    .frame(width: moodButtonWidth, height: moodButtonHeight)
                }
                .buttonStyle(SceneChoiceButtonStyle(chosen: mood == current))
                .accessibilityLabel(Self.moodLabel(mood))
                .accessibilityAddTraits(mood == current ? [.isSelected] : [])
            }
        }
        .padding(CurfewSpacing.xSmall)
        .background(SceneField.fill, in: SceneField.shape)
        .overlay { SceneField.shape.strokeBorder(
            SundownPalette.warmWhite.opacity(0.16),
            lineWidth: 1
        ) }
        .fixedSize()
    }

    private func currentMood(for id: UUID) -> ReflectionMood? {
        if case .mood(let mood) = values[id] {
            return mood
        }
        return nil
    }

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                if case .text(let string) = values[id] {
                    return string
                }
                return ""
            },
            set: { values[id] = .text($0) }
        )
    }

    /// Emoji glyph for `mood`. Kept here (not on the model enum) because it is
    /// a presentation concern.
    static func moodGlyph(_ mood: ReflectionMood) -> String {
        switch mood {
        case .rough: "😣"
        case .low: "🙁"
        case .neutral: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }

    /// Short human label for `mood`.
    static func moodLabel(_ mood: ReflectionMood) -> String {
        switch mood {
        case .rough: "Rough"
        case .low: "Low"
        case .neutral: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }
}

/// The quiet field on the night scene: one step lighter than the panel, a
/// hairline, and the control radius.
enum SceneField {
    static let fill = SundownPalette.warmWhite.opacity(0.07)
    static let shape = RoundedRectangle(cornerRadius: CurfewRadius.control, style: .continuous)
}

/// A single choice on the night scene, fill only: quiet until chosen, then
/// ember, the one accent. No stroke is drawn over the shape, so nothing
/// draws straight lines at its ends; the focus ring follows the shape.
struct SceneChoiceButtonStyle: ButtonStyle {
    var chosen: Bool
    var minWidth: CGFloat?
    var capsule = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = capsule
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: CurfewRadius.control - 2, style: .continuous))
        return configuration.label
            .sundownFont(.button, size: 15)
            .foregroundStyle(chosen ? CurfewTheme.onAccent : SundownPalette.warmWhite)
            .padding(.horizontal, CurfewSpacing.medium)
            .padding(.vertical, CurfewSpacing.small)
            .frame(minWidth: minWidth)
            .background(
                chosen ? CurfewTheme.accentFill : SundownPalette.warmWhite
                    .opacity(capsule ? 0.12 : 0),
                in: shape
            )
            .contentShape(.focusEffect, shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
