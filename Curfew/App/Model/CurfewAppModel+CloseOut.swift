import CurfewKit
import Foundation

/// The evening close-out's one addition: whether the morning's one thing was
/// done, asked on the lock and stored against that day.
@MainActor
extension CurfewAppModel {
    /// The morning's one thing for the day the lock ended, or nil.
    var eveningOneThing: String? {
        let lock = reflectionState.scheduledInterval?.start ?? state.lockDate ?? currentTime
        let calendar = Calendar.current
        let records = journalDayRecords(
            in: lock.addingTimeInterval(-86400) ... lock,
            calendar: calendar
        )
        return EveningCloseOut.oneThing(in: records, forLockAt: lock, calendar: calendar)
    }

    /// Saves the close-out: the yes or no first, then the answers, or skips
    /// the questions when none were answered.
    func saveEveningCloseOut(answers: [ReflectionAnswer], closeOut: EveningCloseOut) {
        closeOut.record { recordOneThingOutcome(done: $0) }
        if answers.isEmpty {
            skipReflection(gate: .evening)
        } else {
            saveReflection(gate: .evening, answers: answers)
        }
    }
}
