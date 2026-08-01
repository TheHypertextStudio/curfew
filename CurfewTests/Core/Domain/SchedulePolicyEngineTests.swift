@testable import Curfew
import Foundation
import Testing

struct SchedulePolicyEngineTests {
    @Test("Weakening changes require a 24-hour cooldown")
    func weakeningChangeHas24HourCooldown() {
        let calendar = Calendar(identifier: .gregorian)
        let engine = SchedulePolicyEngine(calendar: calendar)
        let requestedAt = Date(timeIntervalSince1970: 1_706_788_800) // 2024-02-01T18:00:00Z

        let effectiveDate = engine.earliestEffectiveDate(
            for: .weaker,
            requestedAt: requestedAt
        )

        #expect(effectiveDate.timeIntervalSince(requestedAt) == 86400)
    }

    @Test("Stricter changes apply at next day start")
    func stricterChangeAppliesNextDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current

        let engine = SchedulePolicyEngine(calendar: calendar)
        let requestedAt = Date(timeIntervalSince1970: 1_706_788_800) // 2024-02-01T18:00:00Z

        let effectiveDate = engine.earliestEffectiveDate(
            for: .stricter,
            requestedAt: requestedAt
        )

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: effectiveDate
        )
        #expect(components.year == 2024)
        #expect(components.month == 2)
        #expect(components.day == 2)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test("Later lock time is considered weaker")
    func classifyLaterLockAsWeaker() {
        let engine = SchedulePolicyEngine()
        let current = WeeklySchedule.standardNineToFive
        var proposed = current
        proposed.rules[.monday]?.lockMinutes = 19 * 60

        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .weaker)
    }

    @Test("Earlier lock time is considered stricter")
    func classifyEarlierLockAsStricter() {
        let engine = SchedulePolicyEngine()
        let current = WeeklySchedule.standardNineToFive
        var proposed = current
        proposed.rules[.monday]?.lockMinutes = 16 * 60

        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .stricter)
    }

    @Test("Mode flip from .time to .hours is classified as weaker")
    func modeFlipTimeToHoursIsWeaker() {
        let engine = SchedulePolicyEngine()
        let current = WeeklySchedule.standardNineToFive
        var proposed = current
        proposed.rules[.monday] = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .hours,
            hoursLimitMinutes: 12 * 60
        )

        // This is the bypass repro from the C5 audit finding: a user at
        // T-10 minutes flips to .hours mode with a fresh 12-hour budget
        // and immediately escapes the wall-clock deadline. The engine
        // must classify this as .weaker so the 24-hour cooldown applies.
        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .weaker)
    }

    @Test("Mode flip from .time to .combined is classified as weaker (defensive)")
    func modeFlipTimeToCombinedIsWeaker() {
        let engine = SchedulePolicyEngine()
        let current = WeeklySchedule.standardNineToFive
        var proposed = current
        proposed.rules[.monday] = DayRule(
            isDayOff: false,
            lockMinutes: 18 * 60,
            unlockMinutes: 8 * 60,
            mode: .combined,
            hoursLimitMinutes: 8 * 60
        )

        // Combined mode is strictly stricter than .time alone in steady
        // state (it adds an hours deadline) — but the classifier is
        // defensive: any mode change forces a cooldown because effective
        // strictness depends on runtime `worked` and cannot be evaluated
        // statically. Users get the 24-hour wait for genuine upgrades.
        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .weaker)
    }

    @Test("Hours-limit increase within same mode is weaker")
    func hoursLimitIncreaseIsWeaker() {
        let engine = SchedulePolicyEngine()
        var current = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            if current.rule(for: weekday).isDayOff {
                continue
            }
            current.rules[weekday] = DayRule(
                isDayOff: false,
                lockMinutes: 18 * 60,
                unlockMinutes: 8 * 60,
                mode: .hours,
                hoursLimitMinutes: 8 * 60
            )
        }
        var proposed = current
        proposed.rules[.monday]?.hoursLimitMinutes = 12 * 60

        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .weaker)
    }

    @Test("Hours-limit decrease within same mode is stricter")
    func hoursLimitDecreaseIsStricter() {
        let engine = SchedulePolicyEngine()
        var current = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            if current.rule(for: weekday).isDayOff {
                continue
            }
            current.rules[weekday] = DayRule(
                isDayOff: false,
                lockMinutes: 18 * 60,
                unlockMinutes: 8 * 60,
                mode: .hours,
                hoursLimitMinutes: 10 * 60
            )
        }
        var proposed = current
        proposed.rules[.monday]?.hoursLimitMinutes = 6 * 60

        let classification = engine.classifyChange(from: current, to: proposed)
        #expect(classification == .stricter)
    }
}

struct ScheduleResolutionTests {
    @Test("Schedule window resolves spring-forward DST gaps using local timezone semantics")
    func scheduleWindowResolvesSpringForwardGap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        var schedule = WeeklySchedule.standardNineToFive
        schedule.rules[.sunday] = DayRule(
            isDayOff: false,
            lockMinutes: 150, // 2:30 AM local; does not exist on spring-forward day
            unlockMinutes: 8 * 60
        )

        let reference = try #require(calendar.date(from: .init(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12,
            minute: 0
        )))
        let window = try #require(schedule.scheduleWindow(for: reference, calendar: calendar))
        let components = calendar.dateComponents([.hour, .minute], from: window.lockDate)

        #expect(components.hour == 3)
        #expect(components.minute == 30)
    }

    @Test("Schedule summary sentence reflects next-day lock and unlock times")
    func scheduleSummarySentenceForTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let reference = try #require(calendar.date(from: .init(
            year: 2026,
            month: 2,
            day: 2,
            hour: 9,
            minute: 0
        )))
        let sentence = WeeklySchedule.standardNineToFive.summarySentence(
            forNextDayFrom: reference,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalizedSentence = sentence
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        #expect(normalizedSentence ==
            "Tomorrow, work ends at 6:00 PM and resumes at 8:00 AM.")
    }
}

struct SchedulePresetTests {
    @Test("Schedule presets expose expected lock and unlock defaults")
    func presetDefaults() {
        let nineToFive = WeeklySchedule.standardNineToFive.rule(for: .monday)
        #expect(!nineToFive.isDayOff)
        #expect(nineToFive.lockMinutes == 18 * 60)
        #expect(nineToFive.unlockMinutes == 8 * 60)

        let startup = WeeklySchedule.startupHours.rule(for: .monday)
        #expect(startup.lockMinutes == 20 * 60)
        #expect(startup.unlockMinutes == 8 * 60)

        let halfDay = WeeklySchedule.halfDay.rule(for: .monday)
        #expect(halfDay.lockMinutes == 13 * 60)
        #expect(halfDay.unlockMinutes == 8 * 60)

        let weekend = WeeklySchedule.standardNineToFive.rule(for: .sunday)
        #expect(weekend.isDayOff)
    }
}

struct WarningStageTests {
    @Test("Warning stage boundaries match product spec")
    func stageBoundaries() {
        #expect(WarningStage.stage(forMinutesRemaining: 31) == .none)
        #expect(WarningStage.stage(forMinutesRemaining: 30) == .thirtyMinutes)
        #expect(WarningStage.stage(forMinutesRemaining: 15) == .fifteenMinutes)
        #expect(WarningStage.stage(forMinutesRemaining: 5) == .fiveMinutes)
        #expect(WarningStage.stage(forMinutesRemaining: 2) == .twoMinutes)
        #expect(WarningStage.stage(forMinutesRemaining: 1) == .oneMinute)
        #expect(WarningStage.stage(forMinutesRemaining: 0) == .lockout)
    }

    @Test("Warning overlay opacity matches escalation levels")
    func overlayOpacityLevels() {
        #expect(WarningStage.thirtyMinutes.overlayOpacity == 0)
        #expect(WarningStage.fifteenMinutes.overlayOpacity == 0)
        #expect(WarningStage.fiveMinutes.overlayOpacity == 0.10)
        #expect(WarningStage.twoMinutes.overlayOpacity == 0.25)
        #expect(WarningStage.oneMinute.overlayOpacity == 0.40)
    }
}

struct ExtensionBudgetTrackerTests {
    @Test("Extension budget decrements until exhausted")
    func extensionBudgetDecrements() {
        let now = Date(timeIntervalSince1970: 1_706_788_800)
        let tracker = ExtensionBudgetTracker(
            weeklyLimit: 2,
            extensionMinutes: 15,
            resetWeekday: .monday
        )

        #expect(tracker.requestExtension(at: now))
        #expect(tracker.remaining == 1)
        #expect(tracker.requestExtension(at: now))
        #expect(tracker.remaining == 0)
        #expect(!tracker.requestExtension(at: now))
    }
}
