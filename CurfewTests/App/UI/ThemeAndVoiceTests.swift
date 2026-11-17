@testable import Curfew
import CurfewAtmosphere
import CurfewKit
import Foundation
import SwiftUI
import Testing

/// A theme is a sky palette, a clock style and a voice. Changing one in the
/// editor changes it everywhere those words and that sky appear, and is saved.
@MainActor
struct ThemeAndVoiceTests {
    private func model() -> CurfewAppModel {
        SetupModelFactory.model()
    }

    private func date(_ hour: Int, _ minute: Int, day: Int = 16) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        ))!
    }

    @Test("The model speaks the chosen voice with the person's words over it")
    func modelVoice() {
        let model = model()
        #expect(model.voice == .standard)
        #expect(model.horizonPalette == .standard)
        model.updateTheme {
            $0.voice = .gentle
            $0.palette = .coolTwilight
            $0.customLines = VoiceCustomLines([.lockedHeadline: "Go see the kids."])
        }
        #expect(model.voice.id == "gentle")
        #expect(model.voice.lockedHeadline == "Go see the kids.")
        #expect(model.voice.thirtyMinuteLine == VoicePack.gentle.thirtyMinuteLine)
        #expect(model.horizonPalette == .polar)
        #expect(model.restAppearance.message == "Go see the kids.")
    }

    @Test("A theme change is saved locally and read back by a new store")
    func themePersists() {
        let model = model()
        model.updateTheme {
            $0.voice = .playful
            $0.palette = .warmAmber
            $0.clockStyle = .serif
            $0.customLines = VoiceCustomLines([.sunriseQuestion: "What's first?"])
        }
        let saved = model.restAppearanceStore.load()
        #expect(saved.voice == .playful)
        #expect(saved.palette == .warmAmber)
        #expect(saved.clockStyle == .serif)
        #expect(saved.customLines[.sunriseQuestion] == "What's first?")
    }

    @Test("Changing one choice keeps every other, including Sunrise's wake choices")
    func updatesKeepOtherChoices() {
        let model = model()
        model.updateSunriseWake(enabled: true, leadMinutes: 45)
        model.updateTheme { $0.voice = .gentle }
        #expect(model.restAppearance.sunriseWakeEnabled)
        #expect(model.restAppearance.sunriseLeadMinutes == 45)
        model.updateSunriseWake(onBattery: true)
        #expect(model.restAppearance.voice == .gentle)
    }

    @Test("The lock, Today and the notifications speak the active voice")
    func surfacesSpeakTheVoice() throws {
        let model = model()
        model.updateTheme {
            $0.voice = .playful
            $0.customLines = VoiceCustomLines([.fifteenMinutes: "Wrap it, no new tabs."])
        }
        let lock = LockScreenContent.resolve(
            status: .lockedUntil(date(7, 0, day: 17)), now: date(21, 41), leadMinutes: 30,
            voice: model.voice
        )
        #expect(lock.headline == "Closed for the night.")

        let today = TodayPresentation.resolve(TodaySituation(
            setupComplete: true, enforcing: true, phase: .warning, warningStage: .fifteenMinutes,
            minutesRemaining: 15, upcomingCurfew: date(18, 0), unlockDate: nil, overrideEnds: nil,
            canRequestExtension: true, extensionsRemaining: 2, canCallItADay: true
        ), voice: model.voice)
        #expect(today.line == "Wrap it, no new tabs.")

        let thirty = try #require(WarningNotificationManager.payload(
            for: .thirtyMinutes, voice: model.voice
        ))
        #expect(thirty.body == "Half an hour. Pick your battles.")
        #expect(thirty.title == "30 minutes to curfew")
        #expect(WarningNotificationManager.distractionPayload(voice: model.voice).title == "Hello?")
    }

    @Test("Each tick hands the active voice to the notifications")
    func notificationsFollowTheTheme() {
        let manager = NoOpWarningNotificationManager()
        let model = SetupModelFactory.model(notifications: manager)
        model.updateTheme { $0.voice = .gentle }
        model.tick()
        #expect(manager.voice == model.voice)
    }

    @Test("Sunrise asks the one thing in the active voice, in Settings and on the gate")
    func sunriseQuestion() {
        let model = model()
        model.updateTheme {
            $0.customLines = VoiceCustomLines([.sunriseQuestion: "What's first?"])
        }
        #expect(model.sunriseStepTitle(.oneThing) == "What's first?")
        let pages = model.currentSunrisePages()
        let oneThing = pages.first { $0.prompt?.id == JournalPromptIDs.oneThing }
        #expect(oneThing?.prompt?.text == "What's first?")
        model.updateTheme { $0.customLines = VoiceCustomLines() }
        #expect(model.sunriseStepTitle(.oneThing) == "What is today for?")
    }

    @Test("The preview shows where a rewritten line is said")
    func previewFollowsTheLine() {
        #expect(RestAppearancePreviewSubject(.lockedHeadline) == .lock)
        #expect(RestAppearancePreviewSubject(.overrideQuestion) == .lock)
        #expect(RestAppearancePreviewSubject(.thirtyMinutes) == .warning)
        #expect(RestAppearancePreviewSubject(.lastMinute) == .warning)
        #expect(RestAppearancePreviewSubject(.sunriseGreeting) == .sunrise)
        #expect(RestAppearancePreviewSubject.stage(for: .thirtyMinutes) == .thirtyMinutes)
        #expect(RestAppearancePreviewSubject.stage(for: .lastMinute) == .oneMinute)
        #expect(RestAppearancePreviewSubject.stage(for: .sunriseQuestion) == nil)
        #expect(RestAppearancePreviewSubject.minutes(before: .oneMinute) == 1)
        #expect(RestAppearancePreviewSubject.minutes(before: .thirtyMinutes) == 30)
    }

    @Test("The preview is tonight at 9:41 PM, after a 6 PM curfew, unlocking at 7 AM")
    func previewNight() {
        let preview = RestScreenPreview.tonight(.lock, near: date(10, 15))
        #expect(preview.now == date(21, 41))
        #expect(preview.curfew == date(18, 0))
        #expect(preview.unlock == date(7, 0, day: 17))
        #expect(preview.frame.elevation < 0)
        #expect(preview.frame.moonWeight > 0)
    }

    @Test("VoiceOver hears what the preview shows: the screen, the sky and the words")
    func previewDescription() {
        var draft = RestAppearanceDraft(RestAppearancePreferences())
        draft.palette = .warmAmber
        draft.clockStyle = .serif
        draft.voice = .gentle
        let night = RestScreenPreview.tonight(.lock, near: date(10, 15))
        let lock = RestAppearancePreviewDescription.text(
            subject: .lock, appearance: draft.preferences, warningStage: .fifteenMinutes,
            night: night
        )
        #expect(lock.contains("the Desert sky"))
        #expect(lock.contains("a serif clock"))
        #expect(lock.contains("That's enough for today."))
        #expect(lock.contains("Unlocks at"))
        let warning = RestAppearancePreviewDescription.text(
            subject: .warning, appearance: draft.preferences, warningStage: .oneMinute,
            night: night
        )
        #expect(warning.contains("1 minute before curfew"))
        #expect(warning.contains("Time to rest."))
        draft.customLines = VoiceCustomLines([.lockedHeadline: "Go home."])
        draft.saverMessageEnabled = true
        draft.clockPosition = .lowerLeft
        let saver = RestAppearancePreviewDescription.text(
            subject: .screenSaver, appearance: draft.preferences, warningStage: .fifteenMinutes,
            night: night
        )
        #expect(saver.contains("in the lower left"))
        #expect(saver.contains("Go home."))
    }

    @Test("The editor names the palettes in one plain word each")
    func paletteNames() {
        let names = RestAppearancePreferences.Palette.allCases.map(RestAppearanceCopy.paletteName)
        #expect(names == ["Sundown", "Desert", "Polar"])
        for name in names {
            #expect(!name.contains(" "))
        }
        for line in VoicePack.Line.allCases {
            #expect(!RestAppearanceCopy.moment(line).isEmpty)
        }
    }

    @Test("Each clock style draws in its own face")
    func clockFaces() {
        #expect(RestAppearancePreferences.ClockStyle.rounded.fontDesign == .rounded)
        #expect(RestAppearancePreferences.ClockStyle.standard.fontDesign == .default)
        #expect(RestAppearancePreferences.ClockStyle.serif.fontDesign == .serif)
    }

    @Test("The Today shade is measured on the theme's own sky")
    func shadeUsesPalette() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let frame = HorizonMoment(
            now: start.addingTimeInterval(5 * 3600), dayStart: start,
            curfew: start.addingTimeInterval(11 * 3600),
            nextUnlock: start.addingTimeInterval(24 * 3600)
        ).frame
        #expect(TodaySkyLegibility.ground(for: frame, palette: .desert)
            != TodaySkyLegibility.ground(for: frame, palette: .standard))
    }
}
