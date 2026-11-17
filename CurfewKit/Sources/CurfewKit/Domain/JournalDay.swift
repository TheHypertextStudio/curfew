import Foundation

// The Journal plots what the person did: when they stopped against curfew,
// whether they did the one thing, what extra time they took, and how ready
// they felt. This file holds the two recorded facts (how the day ended and the
// one thing answer) and the per-day record built from the activity log, the
// reflection log and the override log. Everything here is pure so the Journal,
// Today and evening close-out read one tested definition.

/// Fixed prompt identities the Journal reads from reflections. They match the
/// default prompts in ``ReflectionDefaults``.
public enum JournalPromptIDs {
    /// The morning's "one thing" text prompt.
    public static let oneThing = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    /// The morning readiness rating prompt.
    public static let readiness = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    /// The evening "how did today go?" rating prompt.
    public static let eveningRating = UUID(uuidString: "B0000000-0000-0000-0000-000000000003")!
}

/// How a working day ended. Raw values are stored in the activity log's
/// `note` column; never rename them.
public enum DayEndCause: String, CaseIterable, Sendable {
    /// The person ended the day themselves ("Call it a day").
    case calledItADay = "called_it_a_day"
    /// The lock ended the day.
    case lock
}

/// The moment a working day ended and how, measured against the curfew that
/// was scheduled for that day. Stored as one ``ActivityEventKind/dayEnded``
/// event whose timestamp is ``stoppedAt`` and whose minutes are
/// ``minutesFromCurfew``, so the scheduled curfew stays recoverable after the
/// schedule changes.
public struct DayEnding: Equatable, Sendable {
    public let cause: DayEndCause
    /// When the person stopped. For the lock, the moment the lock began.
    public let stoppedAt: Date
    /// The curfew scheduled for that day, before extensions.
    public let scheduledCurfew: Date

    public init(cause: DayEndCause, stoppedAt: Date, scheduledCurfew: Date) {
        self.cause = cause
        self.stoppedAt = stoppedAt
        self.scheduledCurfew = scheduledCurfew
    }

    /// Decodes a ``ActivityEventKind/dayEnded`` event. Returns `nil` for other
    /// kinds, an unknown cause or a missing offset.
    public init?(event: ActivityEvent) {
        guard event.kind == .dayEnded,
              let minutes = event.minutesValue,
              let note = event.note,
              let cause = DayEndCause(rawValue: note)
        else { return nil }
        self.cause = cause
        self.stoppedAt = event.timestamp
        self.scheduledCurfew = event.timestamp.addingTimeInterval(-TimeInterval(minutes) * 60)
    }

    /// Signed whole minutes from the scheduled curfew to the stop, rounded to
    /// the nearest minute. Negative is before curfew.
    public var minutesFromCurfew: Int {
        Int((stoppedAt.timeIntervalSince(scheduledCurfew) / 60).rounded())
    }

    /// The activity event that stores this day end.
    public func activityEvent(id: UUID = UUID()) -> ActivityEvent {
        let minutes = minutesFromCurfew
        return ActivityEvent(
            id: id,
            timestamp: scheduledCurfew.addingTimeInterval(TimeInterval(minutes) * 60),
            gateKind: GateKind.curfew,
            kind: .dayEnded,
            minutesValue: minutes,
            note: cause.rawValue
        )
    }
}

/// The yes or no answer to "did you do the one thing?", stored as one
/// ``ActivityEventKind/oneThingAnswered`` event. The latest answer for a day
/// wins, so a person can change their mind.
public enum OneThingOutcome {
    public static let doneNote = "done"
    public static let notDoneNote = "not_done"

    /// The event recording `done` for the working day containing `date`.
    public static func event(done: Bool, at date: Date, id: UUID = UUID()) -> ActivityEvent {
        ActivityEvent(
            id: id,
            timestamp: date,
            gateKind: GateKind.evening,
            kind: .oneThingAnswered,
            minutesValue: nil,
            note: done ? doneNote : notDoneNote
        )
    }

    /// The answer an event carries, or `nil` for any other event.
    public static func done(from event: ActivityEvent) -> Bool? {
        guard event.kind == .oneThingAnswered else { return nil }
        switch event.note {
        case doneNote: return true
        case notDoneNote: return false
        default: return nil
        }
    }
}

/// Assigns timestamps to working days with an injected calendar.
///
/// Evening facts (the day's end, extra time, the evening close-out and the one
/// thing answer) belong to the day that was ending, so anything before
/// ``eveningCutoffHours`` past midnight counts toward the day before. Morning
/// reflections belong to the calendar day they were written on.
public struct JournalCalendar {
    public var calendar: Calendar
    /// Hours after midnight that still count as the previous evening.
    public var eveningCutoffHours: Int

    public init(calendar: Calendar, eveningCutoffHours: Int = 4) {
        self.calendar = calendar
        self.eveningCutoffHours = eveningCutoffHours
    }

    /// Start of the working day an evening fact at `date` belongs to.
    public func workingDay(forEvening date: Date) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -eveningCutoffHours, to: date) ?? date
        return calendar.startOfDay(for: shifted)
    }

    /// Start of the working day a morning fact at `date` belongs to.
    public func workingDay(forMorning date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

/// Reads and writes the per-day ``DayEnding`` in an activity log.
public enum DayEndLog {
    /// The earliest recorded day end for `workingDay`, or `nil` when nothing
    /// has recorded that day's end. "Stopped" is the earliest of calling it a
    /// day and the lock.
    public static func ending(
        forWorkingDay workingDay: Date,
        in events: [ActivityEvent],
        journal: JournalCalendar
    ) -> DayEnding? {
        events
            .compactMap(DayEnding.init(event:))
            .filter { journal.workingDay(forEvening: $0.scheduledCurfew) == workingDay }
            .min { $0.stoppedAt < $1.stoppedAt }
    }

    /// The window of the activity log worth reading to find a day end for a
    /// curfew at `scheduledCurfew`.
    public static func searchRange(around scheduledCurfew: Date) -> ClosedRange<Date> {
        scheduledCurfew.addingTimeInterval(-36 * 3600) ... scheduledCurfew
            .addingTimeInterval(36 * 3600)
    }
}

/// A rating answer kept with its scale so a 4 of 5 and an 8 of 10 compare.
public struct JournalRating: Equatable, Hashable, Sendable {
    public let value: Int
    public let scale: Int

    public init(value: Int, scale: Int) {
        self.value = value
        self.scale = scale
    }

    /// The rating on a 1 to 5 scale.
    public var fivePoint: Double {
        guard scale > 0 else { return Double(value) }
        return Double(value) / Double(scale) * 5
    }

    init?(_ value: ReflectionValue) {
        switch value {
        case .rating(let rating, let scale): self.init(value: rating, scale: scale)
        case .mood(let mood): self.init(value: mood.score, scale: 5)
        case .text: return nil
        }
    }
}

/// How a day ended against curfew, by the sign of the stop offset.
public enum JournalDayOutcome: Equatable, Sendable {
    /// Stopped before the scheduled curfew.
    case stoppedBeforeCurfew
    /// The lock ended the day at curfew with no extra time.
    case endedByLock
    /// Stopped after the scheduled curfew: extensions, overrides, or both.
    case ranOver
}

/// Everything the Journal shows for one working day.
public struct JournalDayRecord: Equatable, Identifiable {
    /// Start of the working day in the calendar the record was built with.
    public let day: Date
    /// How the day ended, or `nil` when nothing recorded it.
    public let ending: DayEnding?
    public let extensionCount: Int
    /// Minutes granted by extensions that day.
    public let extensionMinutes: Int
    public let overrideCount: Int
    /// Minutes granted by overrides that day.
    public let overrideMinutes: Int
    /// Each override's typed reason, in order.
    public let overrideReasons: [String]
    /// The morning's one thing, trimmed, or `nil` when there was none.
    public let oneThing: String?
    /// The evening answer, or `nil` when unanswered.
    public let oneThingDone: Bool?
    /// Morning readiness.
    public let readiness: JournalRating?
    /// The evening close-out answers in prompt order.
    public let eveningAnswers: [ReflectionAnswer]
    /// The evening "how did today go?" rating.
    public let eveningRating: JournalRating?

    public var id: Date {
        day
    }

    public init(
        day: Date,
        ending: DayEnding? = nil,
        extensionCount: Int? = nil,
        extensionMinutes: Int = 0,
        overrideCount: Int? = nil,
        overrideMinutes: Int = 0,
        overrideReasons: [String] = [],
        oneThing: String? = nil,
        oneThingDone: Bool? = nil,
        readiness: JournalRating? = nil,
        eveningAnswers: [ReflectionAnswer] = [],
        eveningRating: JournalRating? = nil
    ) {
        self.day = day
        self.ending = ending
        self.extensionCount = extensionCount ?? (extensionMinutes > 0 ? 1 : 0)
        self.extensionMinutes = extensionMinutes
        self.overrideCount = overrideCount ?? (overrideMinutes > 0 ? 1 : 0)
        self.overrideMinutes = overrideMinutes
        self.overrideReasons = overrideReasons
        self.oneThing = oneThing
        self.oneThingDone = oneThingDone
        self.readiness = readiness
        self.eveningAnswers = eveningAnswers
        self.eveningRating = eveningRating
    }

    /// The curfew scheduled for that day, before extensions.
    public var scheduledCurfew: Date? {
        ending?.scheduledCurfew
    }

    /// Signed minutes from the scheduled curfew to when the person finally
    /// stopped: the recorded day end plus any override time after the lock.
    /// Extensions already moved the lock, so they are inside the day end.
    public var stopOffsetMinutes: Int? {
        ending.map { $0.minutesFromCurfew + overrideMinutes }
    }

    /// When the person finally stopped.
    public var stoppedAt: Date? {
        guard let scheduledCurfew, let stopOffsetMinutes else { return nil }
        return scheduledCurfew.addingTimeInterval(TimeInterval(stopOffsetMinutes) * 60)
    }

    public var outcome: JournalDayOutcome? {
        stopOffsetMinutes.map { offset in
            offset < 0 ? .stoppedBeforeCurfew : offset == 0 ? .endedByLock : .ranOver
        }
    }

    /// Minutes past the scheduled curfew, zero when on time or early.
    public var minutesOverCurfew: Int {
        max(0, stopOffsetMinutes ?? 0)
    }

    /// Minutes granted by extensions and overrides together.
    public var extraMinutesGranted: Int {
        extensionMinutes + overrideMinutes
    }
}

/// Builds ``JournalDayRecord`` values from the logs.
public enum JournalDayBuilder {
    /// One record per working day that has any Journal fact, ascending.
    /// Days off, and days with nothing recorded, produce no record.
    ///
    /// The override log fills in overrides only on days where the activity log
    /// has none, so an override written to both is counted once.
    public static func records(
        events: [ActivityEvent],
        reflections: [Reflection],
        overrideLog: [OverrideEvent] = [],
        calendar: Calendar,
        eveningCutoffHours: Int = 4
    ) -> [JournalDayRecord] {
        let journal = JournalCalendar(calendar: calendar, eveningCutoffHours: eveningCutoffHours)
        var days: [Date: DayAccumulator] = [:]

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.kind {
            case .dayEnded:
                guard let ending = DayEnding(event: event) else { continue }
                let day = journal.workingDay(forEvening: ending.scheduledCurfew)
                days[day, default: DayAccumulator()].add(ending)
            case .extensionGranted:
                let day = journal.workingDay(forEvening: event.timestamp)
                days[day, default: DayAccumulator()].addExtension(event.minutesValue ?? 0)
            case .overrideGranted:
                let day = journal.workingDay(forEvening: event.timestamp)
                days[day, default: DayAccumulator()]
                    .addOverride(event.minutesValue ?? 0, reason: event.note)
            case .oneThingAnswered:
                guard let done = OneThingOutcome.done(from: event) else { continue }
                days[journal.workingDay(forEvening: event.timestamp), default: DayAccumulator()]
                    .oneThingDone = done
            case .sessionStarted, .sessionEnded, .warningEscalated, .lockoutStarted,
                 .lockoutEnded, .dayOff, .reflectionRecorded:
                continue
            }
        }

        for entry in overrideLog.sorted(by: { $0.timestamp < $1.timestamp }) {
            let day = journal.workingDay(forEvening: entry.timestamp)
            guard days[day]?.hasLoggedOverride != true else { continue }
            days[day, default: DayAccumulator()].addFallbackOverride(
                entry.grantedDurationMinutes, reason: entry.reason
            )
        }

        for reflection in reflections.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch reflection.gate {
            case .morning:
                days[
                    journal.workingDay(forMorning: reflection.timestamp),
                    default: DayAccumulator()
                ]
                .addMorning(reflection)
            case .evening:
                days[
                    journal.workingDay(forEvening: reflection.timestamp),
                    default: DayAccumulator()
                ]
                .addEvening(reflection)
            }
        }

        return days.keys.sorted().compactMap { day in
            days[day]?.record(for: day)
        }
    }
}

/// Per-day fold used by ``JournalDayBuilder``.
private struct DayAccumulator {
    var ending: DayEnding?
    var extensionCount = 0
    var extensionMinutes = 0
    var overrideCount = 0
    var overrideMinutes = 0
    var overrideReasons: [String] = []
    var hasLoggedOverride = false
    var oneThing: String?
    var oneThingDone: Bool?
    var readiness: JournalRating?
    var eveningAnswers: [ReflectionAnswer] = []
    var eveningRating: JournalRating?

    mutating func add(_ candidate: DayEnding) {
        if let ending, ending.stoppedAt <= candidate.stoppedAt {
            return
        }
        ending = candidate
    }

    mutating func addExtension(_ minutes: Int) {
        extensionCount += 1
        extensionMinutes += minutes
    }

    mutating func addOverride(_ minutes: Int, reason: String?) {
        hasLoggedOverride = true
        addFallbackOverride(minutes, reason: reason)
    }

    mutating func addFallbackOverride(_ minutes: Int, reason: String?) {
        overrideCount += 1
        overrideMinutes += minutes
        if let reason, !reason.isEmpty {
            overrideReasons.append(reason)
        }
    }

    mutating func addMorning(_ reflection: Reflection) {
        for answer in reflection.answers {
            switch answer.promptID {
            case JournalPromptIDs.oneThing:
                if case .text(let text) = answer.value {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    oneThing = trimmed.isEmpty ? nil : trimmed
                }
            case JournalPromptIDs.readiness:
                readiness = JournalRating(answer.value)
            default:
                continue
            }
        }
    }

    mutating func addEvening(_ reflection: Reflection) {
        eveningAnswers = reflection.answers
        let ratings = reflection.answers.compactMap { answer in
            JournalRating(answer.value).map { (answer.promptID, $0) }
        }
        eveningRating = ratings.first { $0.0 == JournalPromptIDs.eveningRating }?.1
            ?? ratings.first?.1
    }

    func record(for day: Date) -> JournalDayRecord {
        JournalDayRecord(
            day: day,
            ending: ending,
            extensionCount: extensionCount,
            extensionMinutes: extensionMinutes,
            overrideCount: overrideCount,
            overrideMinutes: overrideMinutes,
            overrideReasons: overrideReasons,
            oneThing: oneThing,
            oneThingDone: oneThingDone,
            readiness: readiness,
            eveningAnswers: eveningAnswers,
            eveningRating: eveningRating
        )
    }
}

/// How long the activity log and reflections are kept. The Journal's year view
/// and year in review read a whole calendar year plus its comparison, so the
/// log keeps at least 400 days.
public enum JournalRetention {
    public static let minimumDays = 400
    public static let activitySeconds = TimeInterval(minimumDays) * 24 * 60 * 60
}
