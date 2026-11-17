import CurfewKit
import SwiftUI

extension EnvironmentValues {
    /// The one thing the close-out asks about, supplied directly by previews
    /// and snapshots instead of being read from the activity log.
    @Entry var eveningOneThingPreview: String?
}

/// The evening close-out as a value: whether it asks about the one thing,
/// the answer, and what may be saved.
struct EveningCloseOut: Equatable {
    let oneThing: String?
    var oneThingDone: Bool?

    init(oneThing: String?, oneThingDone: Bool? = nil) {
        let trimmed = oneThing?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.oneThing = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.oneThingDone = oneThingDone
    }

    var asksOneThing: Bool {
        oneThing != nil
    }

    func canSave(hasAnswers: Bool) -> Bool {
        hasAnswers || (asksOneThing && oneThingDone != nil)
    }

    /// Passes the yes or no to `store` when the question was asked and answered.
    func record(_ store: (Bool) -> Void) {
        guard asksOneThing, let oneThingDone else { return }
        store(oneThingDone)
    }

    /// The morning's one thing for the working day the lock at `lock` ended.
    static func oneThing(
        in records: [JournalDayRecord], forLockAt lock: Date, calendar: Calendar
    ) -> String? {
        let day = JournalCalendar(calendar: calendar).workingDay(forEvening: lock)
        return records.first { calendar.isDate($0.day, inSameDayAs: day) }?.oneThing
    }
}

/// "Close out the day", asked on the lock's own scene: the yes or no about
/// the one thing, then the person's evening questions. Saving or skipping
/// never weakens the lock.
struct EveningReflectionCard: View {
    @Environment(CurfewAppModel.self) private var model
    var voice = VoicePack.standard
    let usesSolidPanels: Bool
    @State private var closeOut: EveningCloseOut?
    @Environment(\.eveningOneThingPreview) private var previewOneThing

    var body: some View {
        let closeOut = closeOut ?? EveningCloseOut(oneThing: nil)
        VStack(alignment: .leading, spacing: CurfewSpacing.large) {
            VStack(alignment: .leading, spacing: CurfewSpacing.xSmall) {
                Text(voice.closeOutTitle)
                    .sundownFont(.title, size: 22)
                Text(voice.closeOutSubtitle)
                    .sundownFont(.body, size: 15)
                    .foregroundStyle(SundownPalette.supportingText)
            }
            if let oneThing = closeOut.oneThing {
                OneThingQuestion(
                    voice: voice, oneThing: oneThing, answer: closeOut.oneThingDone
                ) { done in
                    var next = closeOut
                    next.oneThingDone = done
                    self.closeOut = next
                }
            }
            ReflectionFormView(
                draft: model.reflectionDraft(for: .evening),
                submitLabel: voice.closeOutSave,
                skipLabel: voice.closeOutSkip,
                usesSolidPanels: usesSolidPanels,
                emptyTitle: voice.noQuestionsTitle,
                emptyDetail: voice.noQuestionsDetail,
                extraAnswerGiven: closeOut.oneThingDone != nil,
                onSubmit: { answers in
                    model.saveEveningCloseOut(answers: answers, closeOut: closeOut)
                },
                onSkip: {
                    model.saveEveningCloseOut(answers: [], closeOut: closeOut)
                }
            )
        }
        .foregroundStyle(SundownPalette.warmWhite)
        .padding(CurfewSpacing.xLarge)
        .frame(maxWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .nightPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(voice.closeOutTitle)
        .onAppear {
            // Read the log once; the card must not query it every tick.
            if self.closeOut == nil {
                self.closeOut = EveningCloseOut(oneThing: previewOneThing ?? model.eveningOneThing)
            }
        }
    }
}

/// "Did you do the one thing?" with the morning's words and a yes or no.
private struct OneThingQuestion: View {
    let voice: VoicePack
    let oneThing: String
    let answer: Bool?
    let choose: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            Text(voice.oneThingQuestion)
                .sundownFont(.strong, size: 17)
            HStack(spacing: CurfewSpacing.medium) {
                Label {
                    Text(oneThing)
                        .lineLimit(2)
                } icon: {
                    (answer == true ? HorizonSymbol.oneThingDone : .oneThing).image
                }
                .sundownFont(.title, size: 17)
                Spacer(minLength: CurfewSpacing.large)
                choice(voice.oneThingYes, value: true)
                choice(voice.oneThingNo, value: false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Yes and No read as a pair of choices: outlined until chosen, then
    /// filled ember, the only accent.
    private func choice(_ title: String, value: Bool) -> some View {
        let chosen = value == answer
        return Button(title) { choose(value) }
            .buttonStyle(SceneChoiceButtonStyle(chosen: chosen, capsule: true))
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityLabel("\(title), \(voice.oneThingQuestion)")
    }
}
