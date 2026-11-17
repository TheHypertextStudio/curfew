import CurfewKit
import SwiftUI

/// The override composer's state: progress toward the minimum length, the
/// cooling-off countdown, and whether the hold to confirm is live.
struct OverrideComposerState: Equatable {
    let characters: Int
    let cooldown: Int
    let overridesRemaining: Int
    let minutes: Int
    var minimum = OverrideRequestPolicy.minimumJustificationCharacters
    var voice = VoicePack.standard

    var progress: String {
        voice.overrideProgress(count: min(characters, minimum), minimum: minimum)
    }

    var coolingOff: String? {
        cooldown > 0 ? voice.overrideCoolingOff(seconds: cooldown) : nil
    }

    var canHold: Bool {
        characters >= minimum && cooldown <= 0 && overridesRemaining > 0
    }

    var holdLabel: String {
        voice.overrideHold(minutes: minutes)
    }
}

/// "What can't wait?" The reason, progress toward the minimum, the cooling
/// off, and a hold to confirm with keyboard and VoiceOver paths.
struct OverrideComposer: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var editorFocused: Bool
    var voice = VoicePack.standard

    private var state: OverrideComposerState {
        OverrideComposerState(
            characters: model.overrideReasonDraft
                .trimmingCharacters(in: .whitespacesAndNewlines).count,
            cooldown: Int(ceil(model.overrideCooldownRemaining)),
            overridesRemaining: model.overridesRemaining,
            minutes: model.settings.overrideDurationMinutes,
            voice: voice
        )
    }

    var body: some View {
        @Bindable var model = model
        let state = state
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            Text(voice.overrideQuestion)
                .sundownFont(.title, size: 20)
            TextEditor(text: $model.overrideReasonDraft)
                .foregroundStyle(SundownPalette.warmWhite)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(height: 96)
                .padding(CurfewSpacing.small)
                .background(
                    SundownPalette.inputSurface(usesSolidPanels: reduceTransparency),
                    in: RoundedRectangle(cornerRadius: CurfewRadius.control, style: .continuous)
                )
                .accessibilityLabel(voice.overrideQuestion)
                .accessibilityIdentifier("override-reason")
            HStack(spacing: CurfewSpacing.medium) {
                ProgressView(
                    value: Double(min(state.characters, state.minimum)),
                    total: Double(state.minimum)
                )
                .progressViewStyle(.linear)
                .tint(SundownPalette.warmWhite)
                .frame(width: 96)
                .accessibilityHidden(true)
                Text(state.progress)
                    .monospacedDigit()
                    .accessibilityIdentifier("override-progress")
                Spacer(minLength: 0)
                if let coolingOff = state.coolingOff {
                    Text(coolingOff)
                        .monospacedDigit()
                        .accessibilityIdentifier("override-cooldown")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(SundownPalette.supportingText)
            HStack(spacing: CurfewSpacing.large) {
                HoldToConfirmButton(
                    state.holdLabel, holdingLabel: voice.overrideHolding, symbol: .override,
                    duration: OverrideRequestPolicy.confirmationHoldSeconds, prominent: true
                ) {
                    model.confirmOverride()
                }
                .disabled(!state.canHold)
                .accessibilityIdentifier("override-hold-confirm")
                Button("Not now") {
                    model.isOverrideComposerVisible = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(SundownPalette.supportingText)
                .keyboardShortcut(.cancelAction)
            }
        }
        .foregroundStyle(SundownPalette.warmWhite)
        .padding(CurfewSpacing.xLarge)
        .frame(maxWidth: 520, alignment: .leading)
        .nightPanel()
        .onAppear { editorFocused = true }
    }
}
