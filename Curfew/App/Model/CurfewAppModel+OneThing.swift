import CurfewKit
import Foundation

/// Today's one thing: the answer to the fixed morning text prompt
/// (``JournalPromptIDs/oneThing``) and whether it has been ticked.
///
/// Reads go through the same per-day Journal record the Journal uses, so
/// Today and the Journal agree. Writes go through the morning reflection log
/// and the one thing outcome event.
@MainActor
extension CurfewAppModel {
    /// Today's one thing, or `nil` when the morning has not named one.
    /// Memoised per day on the activity and reflection logs' mutation counts,
    /// so the once-a-second redraw does not query storage.
    var todaysOneThing: TodayOneThing? {
        let day = Calendar.current.startOfDay(for: currentTime)
        let key = OneThingCacheKey(
            model: ObjectIdentifier(self),
            day: day,
            activityMutations: activityRecorder.mutationCount,
            reflectionMutations: reflectionState.recorder.mutationCount,
            revision: oneThingRevision
        )
        if let cached = oneThingCache, cached.key == key {
            return cached.value
        }
        let record = journalDayRecords(in: day ... currentTime).first { $0.day == day }
        let value = record?.oneThing.map { TodayOneThing(
            text: $0,
            isDone: record?.oneThingDone == true
        ) }
        oneThingCache = (key, value)
        return value
    }

    /// Ticks or unticks today's one thing. The latest answer for the day wins,
    /// so unticking is an undo.
    func setOneThingDone(_ done: Bool) {
        guard todaysOneThing != nil else { return }
        recordOneThingOutcome(done: done)
        oneThingRevision += 1
    }

    /// Saves `text` as today's one thing through the morning reflection log,
    /// as Sunrise would, and marks the morning answered so Sunrise does not ask
    /// again today. Returns `false` for blank text.
    @discardableResult
    func saveTodaysOneThing(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let prompt = reflectionConfiguration.morningPrompts
            .first { $0.id == JournalPromptIDs.oneThing }
        let answer = ReflectionAnswer(
            promptID: JournalPromptIDs.oneThing,
            promptTextSnapshot: prompt?.text ?? voice.oneThingQuestion,
            value: .text(trimmed)
        )
        reflectionState.recorder.record(
            Reflection(timestamp: currentTime, gate: .morning, answers: [answer])
        )
        activityRecorder.recordReflectionRecorded(gate: .morning, at: currentTime)
        reflectionState.gatesResolvedToday.insert(.morning)
        oneThingRevision += 1
        return true
    }
}

/// Identifies one memoised read of today's one thing.
private struct OneThingCacheKey: Equatable {
    let model: ObjectIdentifier
    let day: Date
    let activityMutations: Int
    let reflectionMutations: Int
    let revision: Int
}

// Kept at file scope because the model type sits at its stored-property
// budget; there is one model per process, and the key carries its identity.
@MainActor private var oneThingCache: (key: OneThingCacheKey, value: TodayOneThing?)?
@MainActor private var oneThingRevision = 0
