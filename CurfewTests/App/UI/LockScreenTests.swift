import AppKit
@testable import Curfew
import CurfewAtmosphere
@testable import CurfewKit
import Foundation
import Testing

/// The lock's words, the arrival and leaving timeline, the override composer
/// and the evening close-out, as pure values.
@MainActor
struct LockScreenTests {
    private let voice = VoicePack.standard
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: Words

    @Test("Locked: That's the day, the unlock time and the lock symbol")
    func lockedContent() {
        let unlock = now.addingTimeInterval(9 * 3600)
        let content = LockScreenContent.resolve(
            status: .lockedUntil(unlock), now: now, leadMinutes: 30, voice: voice
        )
        #expect(content.headline == "That's the day.")
        #expect(content.line == voice.unlocksAt(unlock))
        #expect(content.symbol == .locked)
        #expect(!content.isLeadIn)
    }

    @Test("Inside the Sunrise lead the lock says Nearly morning and counts down")
    func leadInContent() {
        let unlock = now.addingTimeInterval(12 * 60 - 20)
        let content = LockScreenContent.resolve(
            status: .lockedUntil(unlock), now: now, leadMinutes: 30, voice: voice
        )
        #expect(content.headline == "Nearly morning.")
        #expect(content.line == "Unlocks in 12 minutes")
        #expect(content.symbol == .sunrise)
        #expect(content.isLeadIn)
        let outside = LockScreenContent.resolve(
            status: .lockedUntil(now.addingTimeInterval(31 * 60)), now: now,
            leadMinutes: 30, voice: voice
        )
        #expect(!outside.isLeadIn)
    }

    @Test("The other states speak of this Mac, and release welcomes back")
    func otherStates() {
        let passed = LockScreenContent.resolve(
            status: .stillLocked,
            now: now,
            leadMinutes: 30,
            voice: voice
        )
        #expect(passed.line == "The unlock time has passed. This Mac is still locked.")
        let unknown = LockScreenContent.resolve(
            status: .unknown,
            now: now,
            leadMinutes: 30,
            voice: voice
        )
        #expect(unknown.line == "This Mac stays locked until the schedule lifts.")
        let released = LockScreenContent.resolve(
            status: .released,
            now: now,
            leadMinutes: 30,
            voice: voice
        )
        #expect(released.headline == "Curfew's over. Welcome back.")
        #expect(released.line == nil)
        for content in [passed, unknown, released] {
            #expect(!(content.line ?? "").contains("computer"))
        }
    }

    @Test("VoiceOver hears one clean sentence")
    func accessibilitySummary() {
        let unlock = now.addingTimeInterval(9 * 3600)
        let locked = LockScreenContent.resolve(
            status: .lockedUntil(unlock), now: now, leadMinutes: 30, voice: voice
        )
        #expect(plain(locked.accessibilitySummary).hasPrefix("This Mac is locked until "))
        #expect(locked.accessibilitySummary.filter { $0 == "." }.count == 1)
        #expect(!locked.accessibilitySummary.contains(".."))
        let lead = LockScreenContent.resolve(
            status: .lockedUntil(now.addingTimeInterval(600)), now: now, leadMinutes: 30,
            voice: voice
        )
        #expect(lead.accessibilitySummary == "This Mac unlocks in 10 minutes.")
    }

    // MARK: Override

    @Test("The composer reports progress, then cooling off, then is ready")
    func overrideComposerStates() {
        let short = OverrideComposerState(
            characters: 32,
            cooldown: 299,
            overridesRemaining: 2,
            minutes: 15
        )
        #expect(short.progress == "32 of 50 characters")
        #expect(short.coolingOff == "You can unlock in 4:59")
        #expect(!short.canHold)
        let cooling = OverrideComposerState(
            characters: 60,
            cooldown: 10,
            overridesRemaining: 2,
            minutes: 15
        )
        #expect(cooling.progress == "50 of 50 characters")
        #expect(cooling.coolingOff == "You can unlock in 0:10")
        #expect(!cooling.canHold)
        let ready = OverrideComposerState(
            characters: 60,
            cooldown: 0,
            overridesRemaining: 2,
            minutes: 15
        )
        #expect(ready.coolingOff == nil)
        #expect(ready.canHold)
        #expect(ready.holdLabel == "Hold to unlock for 15 minutes")
        #expect(OverrideComposerState(
            characters: 60,
            cooldown: 0,
            overridesRemaining: 0,
            minutes: 15
        ).canHold == false)
    }

    // MARK: Close-out

    @Test("The close-out asks about the one thing only when there was one")
    func closeOutQuestion() {
        var closeOut = EveningCloseOut(oneThing: "Ship the billing migration")
        #expect(closeOut.asksOneThing)
        #expect(!closeOut.canSave(hasAnswers: false))
        closeOut.oneThingDone = false
        #expect(closeOut.canSave(hasAnswers: false))
        var recorded: [Bool] = []
        closeOut.record { recorded.append($0) }
        #expect(recorded == [false])

        let none = EveningCloseOut(oneThing: nil)
        #expect(!none.asksOneThing)
        var nothing: [Bool] = []
        none.record { nothing.append($0) }
        #expect(nothing.isEmpty)
        #expect(EveningCloseOut(oneThing: "   ").asksOneThing == false)
    }

    @Test("The close-out finds the morning's one thing for the day the lock ended")
    func closeOutFindsTheDay() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let records = try [
            JournalDayRecord(
                day: #require(calendar.date(byAdding: .day, value: -1, to: day)),
                oneThing: "Old"
            ),
            JournalDayRecord(day: day, oneThing: "Ship it")
        ]
        let lock = try #require(calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day))
        #expect(EveningCloseOut
            .oneThing(in: records, forLockAt: lock, calendar: calendar) == "Ship it")
        let afterMidnight = lock.addingTimeInterval(7 * 3600)
        #expect(EveningCloseOut
            .oneThing(in: records, forLockAt: afterMidnight, calendar: calendar) == "Ship it")
    }

    // MARK: Warnings

    @Test("Warning notifications are titled by time to curfew with the stage line as body")
    func warningPayloads() throws {
        let thirty = try #require(WarningNotificationManager.payload(for: .thirtyMinutes))
        #expect(thirty.title == "30 minutes to curfew")
        #expect(thirty.body == "Decide what gets finished and what waits.")
        let one = try #require(WarningNotificationManager.payload(for: .oneMinute))
        #expect(one.title == "1 minute to curfew")
        #expect(one.body == "Last call.")
        for stage in [
            WarningStage.thirtyMinutes,
            .fifteenMinutes,
            .fiveMinutes,
            .twoMinutes,
            .oneMinute
        ] {
            #expect(WarningNotificationManager.payload(for: stage)?.title != "Curfew")
        }
        #expect(WarningNotificationManager.snoozeActionTitle == "1 more minute")
        #expect(WarningNotificationManager.distractionPayload().title == "Still with it?")
    }

    @Test("The notice counts down in minutes and seconds and reads as time to curfew")
    func noticeCountdown() {
        #expect(WarningNoticeContent.countdown(secondsRemaining: 299) == "4:59")
        #expect(WarningNoticeContent.countdown(secondsRemaining: 1800) == "30:00")
        #expect(WarningNoticeContent.countdown(secondsRemaining: -4) == "0:00")
        #expect(WarningNoticeContent
            .spokenCountdown(secondsRemaining: 100) == "2 minutes to curfew")
    }

    @Test("Early notices can be dismissed; the last five minutes stay")
    func noticeVisibility() {
        var visibility = WarningNoticeVisibility()
        #expect(visibility.shouldShow(.thirtyMinutes))
        visibility.dismiss(.thirtyMinutes)
        #expect(!visibility.shouldShow(.thirtyMinutes))
        #expect(visibility.shouldShow(.fifteenMinutes))
        #expect(visibility.shouldShow(.fiveMinutes))
        #expect(visibility.shouldShow(.oneMinute))
        #expect(!WarningNoticeVisibility.isDismissible(.fiveMinutes))
        #expect(WarningNoticeVisibility.isDismissible(.fifteenMinutes))
        #expect(!visibility.shouldShow(.lockout))
    }
}
