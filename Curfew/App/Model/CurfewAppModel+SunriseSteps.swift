import CurfewKit
import Foundation
import SwiftUI

/// Editing the Sunrise steps from Settings: moving, showing, "Can be
/// skipped", and the words and markers each row shows.
@MainActor
extension CurfewAppModel {
    /// Moves one step up (`-1`) or down (`1`), for keyboard and VoiceOver.
    func moveSunriseStep(_ kind: SunriseStepKind, by offset: Int) {
        var steps = sunriseSteps
        guard let index = steps.firstIndex(where: { $0.kind == kind }),
              steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
        updateSunriseSteps(steps)
    }

    /// Moves steps by dragging.
    func moveSunriseSteps(fromOffsets source: IndexSet, toOffset destination: Int) {
        var steps = sunriseSteps
        steps.move(fromOffsets: source, toOffset: destination)
        updateSunriseSteps(steps)
    }

    func setSunriseStep(_ kind: SunriseStepKind, shown: Bool) {
        changeSunriseStep(kind) { $0.isEnabled = shown }
    }

    /// "Can be skipped" in settings; the note is never required either way.
    func setSunriseStep(_ kind: SunriseStepKind, canBeSkipped: Bool) {
        changeSunriseStep(kind) { $0.isRequired = !canBeSkipped }
    }

    private func changeSunriseStep(_ kind: SunriseStepKind, _ change: (inout SunriseStep) -> Void) {
        var steps = sunriseSteps
        guard let index = steps.firstIndex(where: { $0.kind == kind }) else { return }
        change(&steps[index])
        updateSunriseSteps(steps)
    }

    /// Whether this step holds the Mac until it is answered: shown, required,
    /// and a question rather than the note.
    func sunriseStepMustBeAnswered(_ step: SunriseStep) -> Bool {
        step.isEnabled && step.isRequired && step.kind != .lastNightNote
    }

    /// What the person sees for a step, in their words.
    func sunriseStepTitle(_ kind: SunriseStepKind) -> String {
        let prompts = reflectionConfiguration.morningPrompts
        switch kind {
        case .lastNightNote: return "Last night's note"
        case .oneThing: return voice.gateQuestion
        case .readiness:
            return prompts.first { $0.id == JournalPromptIDs.readiness }?.text ?? SunriseVoice
                .readiness
        case .question(let id):
            return prompts.first { $0.id == id }?.text ?? ""
        }
    }
}
