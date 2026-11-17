import CurfewKit
import SwiftUI

/// The Sunrise gate, drawn on the Horizon sky by ``RestScreenView`` under its
/// small clock. The sky holds "Morning."; the ground holds what the person
/// does: last night's note, the question, and "Start the day".
///
/// One page at a time. A required step cannot be skipped, any non-empty
/// answer satisfies it, and a page that cannot be read leaves only "Start the
/// day", so the person is never trapped. Return moves on.
struct SunriseGateView: View {
    /// A still page for previews: nothing takes focus, nothing can be pressed,
    /// nothing is answered or recorded.
    struct Preview {
        let page: SunriseGatePage?
        let isLastPage: Bool
    }

    var preview: Preview?

    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @State private var previewDraft = ReflectionDraft(prompts: [])

    private var page: SunriseGatePage? {
        preview.map(\.page) ?? model.currentSunrisePage
    }

    private var draft: ReflectionDraft {
        preview == nil ? model.reflectionState.morningDraft : previewDraft
    }

    private var canSkip: Bool {
        guard let preview else { return model.canSkipSunrisePage }
        return preview.page?.prompt != nil && preview.page?.isRequired == false
    }

    private var canAdvance: Bool {
        guard let preview else { return model.canAdvanceSunrise }
        return preview.page?.canAdvance(with: nil) ?? true
    }

    private var isLastPage: Bool {
        preview?.isLastPage ?? model.isLastSunrisePage
    }

    /// What ``RestScreenView`` stacks above this view: its top padding, the
    /// small clock and the spacing after it. Used to place the ground block
    /// just below the horizon, where the prototype puts it.
    static let chromeAbove: CGFloat = 32 + 78 + 18
    private static let chromeBelow: CGFloat = 32

    var body: some View {
        GeometryReader { geometry in
            let screen = geometry.size.height + Self.chromeAbove + Self.chromeBelow
            VStack(spacing: 0) {
                Color.clear.frame(height: max(0, screen * 0.19 - Self.chromeAbove))
                Text(SunriseVoice.greeting)
                    .sundownFont(.title, size: 76)
                    .foregroundStyle(SundownPalette.warmWhite)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: CurfewSpacing.xLarge)
                ground
                    .frame(maxWidth: min(880, geometry.size.width * 0.66), alignment: .leading)
                    .frame(
                        minHeight: max(
                            0,
                            geometry.size.height - (screen * 0.775 - Self.chromeAbove)
                        ),
                        alignment: .top
                    )
            }
            .frame(width: geometry.size.width)
        }
        .containerRelativeFrame(.vertical) { length, _ in
            max(320, length - Self.chromeAbove - Self.chromeBelow)
        }
        .allowsHitTesting(preview == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sunrise")
        .accessibilityIdentifier("sunrise-gate")
    }

    private var ground: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.large) {
            if let note = page?.note {
                Label(SunriseVoice.lastNight(note), horizonSymbol: .lastNight)
                    .sundownFont(.strong, size: 17)
                    .foregroundStyle(SundownPalette.supportingText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sunrise-last-night")
            }
            if let prompt = page?.prompt {
                switch prompt.kind {
                case .text:
                    HStack(alignment: .center, spacing: CurfewSpacing.large) {
                        answerField(prompt)
                        actions(page: page, inline: true)
                    }
                case .rating, .mood:
                    Text(prompt.text)
                        .sundownFont(.display, size: 44)
                        .foregroundStyle(SundownPalette.warmWhite)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .center, spacing: CurfewSpacing.large) {
                        if prompt.kind == .rating {
                            SunriseRatingPicker(prompt: prompt, draft: draft)
                        } else {
                            SunriseMoodPicker(prompt: prompt, draft: draft)
                        }
                        Spacer(minLength: CurfewSpacing.large)
                        actions(page: page, inline: true)
                    }
                }
            } else {
                actions(page: page, inline: false)
            }
        }
        .id(model.sunriseRuntime.pageIndex)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.3),
            value: model.sunriseRuntime.pageIndex
        )
        .task(id: model.sunriseRuntime.pageIndex) {
            guard preview == nil else { return }
            // The window becomes key a moment after it is ordered in.
            try? await Task.sleep(for: .milliseconds(150))
            fieldFocused = true
        }
    }

    private func answerField(_ prompt: ReflectionPrompt) -> some View {
        VStack(spacing: CurfewSpacing.small) {
            TextField(
                "", text: textBinding(prompt.id),
                prompt: Text(prompt.text).foregroundStyle(SundownPalette.warmWhite.opacity(0.6))
            )
            .textFieldStyle(.plain)
            .sundownFont(.display, size: 48)
            .foregroundStyle(SundownPalette.warmWhite)
            .focused($fieldFocused)
            .onSubmit { model.advanceSunrise() }
            .accessibilityLabel(prompt.text)
            .accessibilityIdentifier("sunrise-answer")
            Rectangle()
                .fill(SundownPalette.warmWhite.opacity(fieldFocused ? 0.8 : 0.5))
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }

    private func actions(page: SunriseGatePage?, inline: Bool) -> some View {
        HStack(spacing: CurfewSpacing.large) {
            if !inline {
                Spacer(minLength: 0)
            }
            if canSkip {
                Button(SunriseVoice.skip) { model.skipSunrisePage() }
                    .buttonStyle(.plain)
                    .sundownFont(.button, size: 15)
                    .foregroundStyle(SundownPalette.supportingText)
                    .accessibilityIdentifier("sunrise-skip")
            }
            primaryButton(page: page)
        }
        .fixedSize(horizontal: inline, vertical: false)
    }

    /// The one primary action, at the shared primary size. Until a required
    /// answer is given it stays full size but turns into an outlined, muted
    /// capsule, so it reads as waiting rather than as a smaller control.
    @ViewBuilder
    private func primaryButton(page _: SunriseGatePage?) -> some View {
        if canAdvance {
            Button {
                model.advanceSunrise()
            } label: {
                primaryLabel
            }
            .buttonStyle(.horizonGlassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("sunrise-start")
        } else {
            // Same footprint as the primary capsule, drawn as an outline. Not
            // a button until it can act, so nothing draws a control bezel.
            primaryLabel
                .sundownFont(.button, size: 15)
                .foregroundStyle(SundownPalette.warmWhite.opacity(0.55))
                .padding(.horizontal, CurfewSpacing.large)
                .padding(.vertical, CurfewSpacing.small)
                .overlay(Capsule().inset(by: 0.5).stroke(
                    SundownPalette.warmWhite.opacity(0.45), lineWidth: 1
                ))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Answer the question first.")
                .accessibilityIdentifier("sunrise-start")
        }
    }

    @ViewBuilder
    private var primaryLabel: some View {
        if isLastPage {
            Label(SunriseVoice.startTheDay, horizonSymbol: .sunrise)
        } else {
            Text(SunriseVoice.next)
        }
    }

    private func textBinding(_ id: UUID) -> Binding<String> {
        let draft = draft
        return Binding(
            get: {
                if case .text(let text) = draft.values[id] {
                    return text
                }
                return ""
            },
            set: { draft.values[id] = .text($0) }
        )
    }
}

/// A 1…N rating on the ground: one circle per value, the chosen one ember.
private struct SunriseRatingPicker: View {
    let prompt: ReflectionPrompt
    @Bindable var draft: ReflectionDraft
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 52

    var body: some View {
        let scale = max(2, prompt.ratingMax)
        let chosen: Int = if case .rating(let value, _) = draft.values[prompt.id] {
            value
        } else {
            0
        }
        HStack(spacing: CurfewSpacing.small) {
            ForEach(1 ... scale, id: \.self) { value in
                Button {
                    draft.values[prompt.id] = .rating(value: value, scale: scale)
                } label: {
                    Text("\(value)")
                        .sundownFont(.button, size: 20)
                        .frame(width: size, height: size)
                        .background(
                            value == chosen ? CurfewTheme.accentFill : SundownPalette.warmWhite
                                .opacity(0.14),
                            in: Circle()
                        )
                        .foregroundStyle(SundownPalette.warmWhite)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) out of \(scale)")
                .accessibilityAddTraits(value == chosen ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.text)
    }
}

/// A five-point mood pick on the ground.
private struct SunriseMoodPicker: View {
    let prompt: ReflectionPrompt
    @Bindable var draft: ReflectionDraft

    var body: some View {
        let chosen: ReflectionMood? = if case .mood(let mood) = draft.values[prompt.id] {
            mood
        } else {
            nil
        }
        HStack(spacing: CurfewSpacing.small) {
            ForEach(ReflectionMood.allCases, id: \.self) { mood in
                Button {
                    draft.values[prompt.id] = .mood(mood)
                } label: {
                    Text(ReflectionFormView.moodLabel(mood))
                        .sundownFont(.button, size: 14)
                        .padding(.horizontal, CurfewSpacing.medium)
                        .padding(.vertical, CurfewSpacing.small)
                        .background(
                            mood == chosen ? CurfewTheme.accentFill : SundownPalette.warmWhite
                                .opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(SundownPalette.warmWhite)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mood == chosen ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.text)
    }
}
