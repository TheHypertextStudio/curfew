import CurfewKit
import Foundation

/// Records the two Journal facts and reads the per-day records.
///
/// - How the day ended: the lock path records "the lock ended it" once per
///   working day; ``recordCalledItADay()`` records "ended it themselves" for
///   the Call it a day action. The earliest wins, so whichever comes first is
///   the stop.
/// - Whether the one thing was done: ``recordOneThingOutcome(done:)``.
///
/// Both are local activity events; neither changes a wire shape.
@MainActor
extension CurfewAppModel {
    /// The day's scheduled curfew: the effective lock moment minus the minutes
    /// that moved it today (extensions and snoozes).
    private func scheduledCurfew(forLockAt lockDate: Date) -> Date {
        let moved = extensionMinutesGrantedToday + snoozeMinutesGrantedToday
        return lockDate.addingTimeInterval(-TimeInterval(moved) * 60)
    }

    private var journalCalendar: JournalCalendar {
        JournalCalendar(calendar: .current)
    }

    /// Appends `ending` unless that working day's end is already recorded.
    /// Reads the store, so a relaunch never writes a second record.
    @discardableResult
    private func appendDayEndIfMissing(_ ending: DayEnding) -> Bool {
        let day = journalCalendar.workingDay(forEvening: ending.scheduledCurfew)
        let nearby = activityRecorder
            .events(in: DayEndLog.searchRange(around: ending.scheduledCurfew))
        guard DayEndLog.ending(forWorkingDay: day, in: nearby, journal: journalCalendar) == nil
        else {
            return false
        }
        activityRecorder.recordJournalEvent(ending.activityEvent())
        return true
    }

    /// Called from the armed tick. While locked, records that the lock ended
    /// the day when nothing has recorded that day's end yet. Checks the log
    /// once per working day per process.
    func recordDayEndedByLockIfNeeded() {
        guard state.phase == .locked else { return }
        let lockDate = state.lockDate ?? currentTime
        let curfew = scheduledCurfew(forLockAt: lockDate)
        let day = journalCalendar.workingDay(forEvening: curfew)
        guard journalDayEndCheckedDay != day else { return }
        journalDayEndCheckedDay = day
        appendDayEndIfMissing(DayEnding(cause: .lock, stoppedAt: lockDate, scheduledCurfew: curfew))
    }

    /// Records that the person ended the day themselves, now. For the Call it
    /// a day action; this does not lock. Returns `false` outside a working
    /// window or when the day's end is already recorded.
    @discardableResult
    func recordCalledItADay() -> Bool {
        guard state.phase == .working || state.phase == .warning,
              let lockDate = state.lockDate
        else { return false }
        return appendDayEndIfMissing(DayEnding(
            cause: .calledItADay,
            stoppedAt: currentTime,
            scheduledCurfew: scheduledCurfew(forLockAt: lockDate)
        ))
    }

    /// Records whether the morning's one thing was done. During the lock the
    /// answer belongs to the day the lock ended, even after midnight. The
    /// latest answer for a day wins.
    func recordOneThingOutcome(done: Bool) {
        let anchor = state.phase == .locked ? state.lockDate ?? currentTime : currentTime
        activityRecorder.recordJournalEvent(OneThingOutcome.event(done: done, at: anchor))
    }

    /// Per-day Journal records for working days in `range`, built from the
    /// activity log, reflections and the override log.
    func journalDayRecords(
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [JournalDayRecord] {
        // Read a day either side so late evenings and their day ends are whole.
        let padded = range.lowerBound.addingTimeInterval(-86400) ... range.upperBound
            .addingTimeInterval(86400)
        let records = JournalDayBuilder.records(
            events: activityRecorder.events(in: padded),
            reflections: reflectionState.recorder.reflections(in: padded),
            overrideLog: overrideEvents.filter { padded.contains($0.timestamp) },
            calendar: calendar
        )
        let first = calendar.startOfDay(for: range.lowerBound)
        return records.filter { $0.day >= first && $0.day <= range.upperBound }
    }
}
