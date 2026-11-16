@testable import CurfewKit
import Foundation

/// Hand-built calendars, dates, events, reflections and records for the
/// Journal tests. Every helper is deterministic so a failure points at the
/// definition under test, never at the clock or the machine's time zone.
enum JournalFixture {
    /// Gregorian, UTC, weeks starting on Monday.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Gregorian in Los Angeles, which leaves daylight saving time on
    /// Sunday, November 1, 2026.
    static var losAngeles: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        calendar: Calendar = utc
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    static func minutes(_ value: Int) -> TimeInterval {
        TimeInterval(value * 60)
    }

    static func dayEnd(
        _ cause: DayEndCause,
        curfew: Date,
        offset: Int
    ) -> ActivityEvent {
        DayEnding(
            cause: cause,
            stoppedAt: curfew.addingTimeInterval(minutes(offset)),
            scheduledCurfew: curfew
        ).activityEvent()
    }

    static func extensionGranted(_ minutes: Int, at date: Date) -> ActivityEvent {
        ActivityEvent(
            timestamp: date, gateKind: GateKind.curfew, kind: .extensionGranted,
            minutesValue: minutes, note: nil
        )
    }

    static func overrideGranted(_ minutes: Int, reason: String, at date: Date) -> ActivityEvent {
        ActivityEvent(
            timestamp: date, gateKind: GateKind.curfew, kind: .overrideGranted,
            minutesValue: minutes, note: reason
        )
    }

    static func morning(
        at date: Date,
        oneThing: String?,
        ready: Int? = nil,
        scale: Int = 5
    ) -> Reflection {
        var answers: [ReflectionAnswer] = []
        if let oneThing {
            answers.append(ReflectionAnswer(
                promptID: JournalPromptIDs.oneThing,
                promptTextSnapshot: "What's the one thing that matters most today?",
                value: .text(oneThing)
            ))
        }
        if let ready {
            answers.append(ReflectionAnswer(
                promptID: JournalPromptIDs.readiness,
                promptTextSnapshot: "How prepared do you feel to start work?",
                value: .rating(value: ready, scale: scale)
            ))
        }
        return Reflection(timestamp: date, gate: .morning, answers: answers)
    }

    static func evening(at date: Date, finished: String, rating: Int) -> Reflection {
        Reflection(timestamp: date, gate: .evening, answers: [
            ReflectionAnswer(
                promptID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
                promptTextSnapshot: "What did you finish today?",
                value: .text(finished)
            ),
            ReflectionAnswer(
                promptID: JournalPromptIDs.eveningRating,
                promptTextSnapshot: "How did today go?",
                value: .rating(value: rating, scale: 5)
            )
        ])
    }

    /// A record on `day` (midnight UTC) with an 18:00 curfew and the given
    /// stop offset. `offset == nil` leaves the stop unknown.
    static func record(
        _ day: Date,
        offset: Int?,
        cause: DayEndCause? = nil,
        done: Bool? = nil,
        ready: Int? = nil,
        overrideMinutes: Int = 0,
        extensionMinutes: Int = 0
    ) -> JournalDayRecord {
        let curfew = day.addingTimeInterval(minutes(18 * 60))
        let ending = offset.map { value in
            DayEnding(
                cause: cause ?? (value < 0 ? .calledItADay : .lock),
                stoppedAt: curfew.addingTimeInterval(minutes(value - overrideMinutes)),
                scheduledCurfew: curfew
            )
        }
        return JournalDayRecord(
            day: day,
            ending: ending,
            extensionMinutes: extensionMinutes,
            overrideMinutes: overrideMinutes,
            oneThing: done == nil ? nil : "Ship it",
            oneThingDone: done,
            readiness: ready.map { JournalRating(value: $0, scale: 5) }
        )
    }

    /// Consecutive days starting at `start`, one per entry.
    static func days(from start: Date, count: Int, calendar: Calendar = utc) -> [Date] {
        (0 ..< count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
}
