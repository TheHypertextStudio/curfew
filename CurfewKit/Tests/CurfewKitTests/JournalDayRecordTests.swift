@testable import CurfewKit
import Foundation
import Testing

private typealias F = JournalFixture

struct DayEndingStorageTests {
    @Test("A day end round-trips through one activity event with signed minutes")
    func roundTrip() throws {
        let curfew = F.date(2026, 11, 16, 18, 0)
        let ending = DayEnding(
            cause: .calledItADay,
            stoppedAt: curfew.addingTimeInterval(F.minutes(-42)),
            scheduledCurfew: curfew
        )
        let event = ending.activityEvent()

        #expect(event.kind == .dayEnded)
        #expect(event.gateKind == GateKind.curfew)
        #expect(event.minutesValue == -42)
        #expect(event.note == "called_it_a_day")
        #expect(event.timestamp == curfew.addingTimeInterval(F.minutes(-42)))
        #expect(try #require(DayEnding(event: event)) == ending)
    }

    @Test("The scheduled curfew is recovered from the stored event, not the schedule")
    func curfewRecoveredAfterScheduleChange() throws {
        let curfew = F.date(2026, 11, 16, 17, 30)
        let event = F.dayEnd(.lock, curfew: curfew, offset: 15)
        let decoded = try #require(DayEnding(event: event))
        #expect(decoded.scheduledCurfew == curfew)
        #expect(decoded.minutesFromCurfew == 15)
        #expect(decoded.cause == .lock)
    }

    @Test("Other kinds and unknown causes do not decode as a day end")
    func rejectsOtherEvents() {
        let other = F.extensionGranted(15, at: F.date(2026, 11, 16, 17, 50))
        #expect(DayEnding(event: other) == nil)
        let unknown = ActivityEvent(
            timestamp: F.date(2026, 11, 16, 18), gateKind: GateKind.curfew,
            kind: .dayEnded, minutesValue: 0, note: "wandered off"
        )
        #expect(DayEnding(event: unknown) == nil)
        let missingMinutes = ActivityEvent(
            timestamp: F.date(2026, 11, 16, 18), gateKind: GateKind.curfew,
            kind: .dayEnded, minutesValue: nil, note: "lock"
        )
        #expect(DayEnding(event: missingMinutes) == nil)
    }

    @Test("Minutes from curfew round to the nearest minute")
    func roundsToMinute() {
        let curfew = F.date(2026, 11, 16, 18)
        let early = DayEnding(
            cause: .calledItADay,
            stoppedAt: curfew.addingTimeInterval(-89),
            scheduledCurfew: curfew
        )
        #expect(early.minutesFromCurfew == -1)
        #expect(early.activityEvent().minutesValue == -1)
    }

    @Test("The one thing answer is stored as an evening activity event, last answer wins")
    func oneThingEvents() {
        let yes = OneThingOutcome.event(done: true, at: F.date(2026, 11, 16, 18))
        let no = OneThingOutcome.event(done: false, at: F.date(2026, 11, 16, 18, 5))
        #expect(yes.kind == .oneThingAnswered)
        #expect(yes.gateKind == GateKind.evening)
        #expect(yes.note == "done")
        #expect(no.note == "not_done")
        #expect(OneThingOutcome.done(from: yes) == true)
        #expect(OneThingOutcome.done(from: no) == false)
        #expect(OneThingOutcome.done(from: F.extensionGranted(15, at: .now)) == nil)
    }

    @Test("Looking up a working day's end finds the earliest recorded stop")
    func dayEndLookup() throws {
        let calendar = F.utc
        let journal = JournalCalendar(calendar: calendar)
        let curfew = F.date(2026, 11, 16, 18)
        let events = [
            F.dayEnd(.lock, curfew: curfew, offset: 0),
            F.dayEnd(.calledItADay, curfew: curfew, offset: -20)
        ]
        let found = try #require(DayEndLog.ending(
            forWorkingDay: F.date(2026, 11, 16), in: events, journal: journal
        ))
        #expect(found.cause == .calledItADay)
        #expect(DayEndLog.ending(
            forWorkingDay: F.date(2026, 11, 17), in: events, journal: journal
        ) == nil)
    }
}

struct JournalDayBuilderTests {
    private let calendar = F.utc

    private func build(
        _ events: [ActivityEvent],
        _ reflections: [Reflection] = [],
        overrideLog: [OverrideEvent] = [],
        calendar: Calendar? = nil
    ) -> [JournalDayRecord] {
        JournalDayBuilder.records(
            events: events,
            reflections: reflections,
            overrideLog: overrideLog,
            calendar: calendar ?? self.calendar
        )
    }

    @Test("No data builds no records and an empty summary")
    func noData() {
        #expect(build([]).isEmpty)
        let summary = JournalSummary(records: [])
        #expect(summary.days == 0)
        #expect(summary.stoppedBeforeCurfewRate == nil)
        #expect(summary.oneThingRate == nil)
        #expect(summary.readinessAverage == nil)
        #expect(summary.medianStopOffsetMinutes == nil)
    }

    @Test("Calling it a day before curfew is an early stop")
    func calledItADayEarly() throws {
        let curfew = F.date(2026, 11, 16, 18)
        let record = try #require(build([F.dayEnd(.calledItADay, curfew: curfew, offset: -30)])
            .first)
        #expect(record.day == F.date(2026, 11, 16))
        #expect(record.scheduledCurfew == curfew)
        #expect(record.stopOffsetMinutes == -30)
        #expect(record.stoppedAt == curfew.addingTimeInterval(F.minutes(-30)))
        #expect(record.outcome == .stoppedBeforeCurfew)
        #expect(record.ending?.cause == .calledItADay)
        #expect(record.extraMinutesGranted == 0)
        #expect(record.minutesOverCurfew == 0)
    }

    @Test("The lock ending the day at curfew is neither early nor over")
    func lockAtCurfew() throws {
        let curfew = F.date(2026, 11, 16, 18)
        let record = try #require(build([F.dayEnd(.lock, curfew: curfew, offset: 0)]).first)
        #expect(record.stopOffsetMinutes == 0)
        #expect(record.outcome == .endedByLock)
    }

    @Test("A day with both an extension and an override runs over by both")
    func extensionAndOverride() throws {
        let curfew = F.date(2026, 11, 16, 18)
        let reason = "The release branch will not build and the review slot is tomorrow."
        let records = build([
            F.extensionGranted(15, at: curfew.addingTimeInterval(F.minutes(-10))),
            F.dayEnd(.lock, curfew: curfew, offset: 15),
            F.overrideGranted(30, reason: reason, at: curfew.addingTimeInterval(F.minutes(40)))
        ])
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.extensionMinutes == 15)
        #expect(record.extensionCount == 1)
        #expect(record.overrideMinutes == 30)
        #expect(record.overrideCount == 1)
        #expect(record.overrideReasons == [reason])
        #expect(record.extraMinutesGranted == 45)
        #expect(record.stopOffsetMinutes == 45)
        #expect(record.minutesOverCurfew == 45)
        #expect(record.outcome == .ranOver)
        #expect(record.stoppedAt == curfew.addingTimeInterval(F.minutes(45)))
    }

    @Test("A late night that crosses midnight stays on the day it started")
    func crossesMidnight() throws {
        let curfew = F.date(2026, 11, 16, 23, 30)
        let records = build([
            F.extensionGranted(15, at: F.date(2026, 11, 16, 23, 20)),
            F.dayEnd(.lock, curfew: curfew, offset: 15),
            F.overrideGranted(30, reason: "Production is down", at: F.date(2026, 11, 17, 0, 10)),
            OneThingOutcome.event(done: true, at: F.date(2026, 11, 17, 0, 50))
        ])
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.day == F.date(2026, 11, 16))
        #expect(record.stopOffsetMinutes == 45)
        #expect(record.oneThingDone == true)
    }

    @Test("A curfew scheduled after midnight belongs to the evening before")
    func curfewAfterMidnight() throws {
        let curfew = F.date(2026, 11, 17, 0, 30)
        let record = try #require(build([F.dayEnd(.lock, curfew: curfew, offset: 0)]).first)
        #expect(record.day == F.date(2026, 11, 16))
    }

    @Test("A schedule change mid-week measures each day against its own curfew")
    func scheduleChangeMidWeek() {
        let monday = F.date(2026, 11, 16, 18)
        let wednesday = F.date(2026, 11, 18, 17)
        let records = build([
            F.dayEnd(.lock, curfew: monday, offset: 0),
            F.dayEnd(.calledItADay, curfew: wednesday, offset: -10)
        ])
        #expect(records.map(\.day) == [F.date(2026, 11, 16), F.date(2026, 11, 18)])
        #expect(records[0].scheduledCurfew == monday)
        #expect(records[1].scheduledCurfew == wednesday)
        #expect(records[1].stopOffsetMinutes == -10)
        #expect(records[1].stoppedAt == F.date(2026, 11, 18, 16, 50))
    }

    @Test("A day off produces no record")
    func dayOff() {
        let records = build([
            F.dayEnd(.lock, curfew: F.date(2026, 11, 20, 18), offset: 0),
            ActivityEvent(
                timestamp: F.date(2026, 11, 21, 9), gateKind: GateKind.curfew,
                kind: .dayOff, minutesValue: nil, note: nil
            ),
            ActivityEvent(
                timestamp: F.date(2026, 11, 21, 12), gateKind: GateKind.curfew,
                kind: .lockoutEnded, minutesValue: nil, note: nil
            ),
            F.dayEnd(.lock, curfew: F.date(2026, 11, 23, 18), offset: 0)
        ])
        #expect(records.map(\.day) == [F.date(2026, 11, 20), F.date(2026, 11, 23)])
    }

    @Test("Days follow the injected calendar across a daylight saving change")
    func daylightSavingChange() {
        let la = F.losAngeles
        // Clocks go back at 2:00 AM on Sunday, November 1, 2026.
        let saturday = F.date(2026, 10, 31, 18, calendar: la)
        let sunday = F.date(2026, 11, 1, 18, calendar: la)
        let monday = F.date(2026, 11, 2, 18, calendar: la)
        let records = build(
            [
                F.dayEnd(.lock, curfew: saturday, offset: 0),
                F.dayEnd(.calledItADay, curfew: sunday, offset: -5),
                F.dayEnd(.lock, curfew: monday, offset: 0)
            ],
            calendar: la
        )
        #expect(records.map(\.day) == [
            F.date(2026, 10, 31, calendar: la),
            F.date(2026, 11, 1, calendar: la),
            F.date(2026, 11, 2, calendar: la)
        ])
        #expect(records[1].stopOffsetMinutes == -5)
        let review = JournalYearInReview(records: records, calendar: la)
        #expect(review.typicalStopMinuteOfDay == 18 * 60)
    }

    @Test("A time zone change keeps each stop relative to its own curfew")
    func timeZoneChange() throws {
        // 18:00 in Los Angeles is 02:00 UTC the next day.
        let curfew = F.date(2026, 11, 16, 18, calendar: F.losAngeles)
        let events = [F.dayEnd(.calledItADay, curfew: curfew, offset: -20)]
        let inLA = try #require(build(events, calendar: F.losAngeles).first)
        let inUTC = try #require(build(events, calendar: F.utc).first)
        #expect(inLA.day == F.date(2026, 11, 16, calendar: F.losAngeles))
        #expect(inUTC.day == F.date(2026, 11, 16))
        #expect(inLA.stopOffsetMinutes == -20)
        #expect(inUTC.stopOffsetMinutes == -20)
    }

    @Test("Morning and evening reflections and the one thing answer join the day")
    func reflectionsJoin() throws {
        let curfew = F.date(2026, 11, 16, 18)
        let records = build(
            [
                F.dayEnd(.lock, curfew: curfew, offset: 0),
                OneThingOutcome.event(done: false, at: F.date(2026, 11, 16, 12)),
                OneThingOutcome.event(done: true, at: F.date(2026, 11, 16, 18, 2))
            ],
            [
                F.morning(
                    at: F.date(2026, 11, 16, 8, 5),
                    oneThing: "  Ship the migration  ",
                    ready: 4
                ),
                F.evening(at: curfew, finished: "Shipped it.", rating: 3)
            ]
        )
        let record = try #require(records.first)
        #expect(record.oneThing == "Ship the migration")
        #expect(record.oneThingDone == true)
        #expect(record.readiness == JournalRating(value: 4, scale: 5))
        #expect(record.readiness?.fivePoint == 4)
        #expect(record.eveningRating == JournalRating(value: 3, scale: 5))
        #expect(record.eveningAnswers.count == 2)
    }

    @Test("A morning with no recorded stop still makes a record with an unknown stop")
    func morningOnly() throws {
        let record = try #require(build(
            [],
            [F.morning(at: F.date(2026, 11, 16, 8), oneThing: "", ready: 8, scale: 10)]
        ).first)
        #expect(record.ending == nil)
        #expect(record.stopOffsetMinutes == nil)
        #expect(record.outcome == nil)
        #expect(record.oneThing == nil)
        #expect(record.readiness?.fivePoint == 4)
    }

    @Test("The override log fills in overrides the activity log missed, without double counting")
    func overrideLogFallback() {
        let curfew = F.date(2026, 11, 16, 18)
        let tuesday = F.date(2026, 11, 17, 18)
        let log = [
            OverrideEvent(
                timestamp: curfew.addingTimeInterval(F.minutes(5)), deviceName: "Mac",
                reason: "Payroll export failed", grantedDurationMinutes: 30
            ),
            OverrideEvent(
                timestamp: tuesday.addingTimeInterval(F.minutes(5)), deviceName: "Mac",
                reason: "Contract signature", grantedDurationMinutes: 30
            )
        ]
        let records = build(
            [
                F.dayEnd(.lock, curfew: curfew, offset: 0),
                F.dayEnd(.lock, curfew: tuesday, offset: 0),
                F.overrideGranted(
                    30,
                    reason: "Contract signature",
                    at: tuesday
                        .addingTimeInterval(F.minutes(5))
                )
            ],
            overrideLog: log
        )
        #expect(records[0].overrideMinutes == 30)
        #expect(records[0].overrideReasons == ["Payroll export failed"])
        #expect(records[1].overrideMinutes == 30)
        #expect(records[1].overrideCount == 1)
    }
}
