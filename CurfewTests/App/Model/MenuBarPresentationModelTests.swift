import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct MenuBarPresentationModelTests {
    @Test("Status lines name the curfew, the minutes left and the unlock in locale time")
    func statusLinesUseTheVoice() {
        let model = makeTrustedModel()
        let lock = Date(timeIntervalSince1970: 1_800_000_000)
        let unlock = lock.addingTimeInterval(13 * 3600)
        let lockText = lock.formatted(date: .omitted, time: .shortened)
        let unlockText = unlock.formatted(date: .omitted, time: .shortened)
        model.currentTime = lock.addingTimeInterval(-90 * 60)

        model.state = CurfewEvaluation(
            phase: .working, warningStage: .none, minutesRemaining: 90,
            canRequestExtension: false, lockDate: lock, unlockDate: unlock
        )
        #expect(model.statusLine == "Curfew at \(lockText)")
        #expect(!model.statusLine.contains("Work hours"))

        model.currentTime = lock.addingTimeInterval(-12 * 60)
        model.state = CurfewEvaluation(
            phase: .warning, warningStage: .fifteenMinutes, minutesRemaining: 12,
            canRequestExtension: true, lockDate: lock, unlockDate: unlock
        )
        #expect(model.statusLine == "Curfew in 12 minutes")

        model.state = CurfewEvaluation(
            phase: .warning, warningStage: .oneMinute, minutesRemaining: 1,
            canRequestExtension: false, lockDate: lock, unlockDate: unlock
        )
        #expect(model.statusLine == "Curfew in 1 minute")

        model.currentTime = lock.addingTimeInterval(60)
        model.state = .locked(lockDate: lock, unlockDate: unlock)
        #expect(model.statusLine == "Locked until \(unlockText)")
        #expect(model.menuBarSymbolName == "lock.fill")

        model.state = .dayOff
        #expect(model.statusLine == "No curfew today")
    }

    @Test("During an override the menu bar never names a curfew that has passed")
    func overrideNeverShowsPastCurfew() {
        let model = makeTrustedModel()
        model.started = true
        let lock = Date(timeIntervalSince1970: 1_800_000_000)
        let unlock = lock.addingTimeInterval(13 * 3600)
        let relock = lock.addingTimeInterval(45 * 60)
        model.currentTime = lock.addingTimeInterval(20 * 60)
        model.overrideUntil = relock
        model.state = CurfewEvaluation(
            phase: .working, warningStage: .none, minutesRemaining: 25,
            canRequestExtension: false, lockDate: lock, unlockDate: unlock
        )
        let lockText = lock.formatted(date: .omitted, time: .shortened)
        let relockText = relock.formatted(date: .omitted, time: .shortened)
        #expect(!model.menuBarHeaderLine.contains(lockText))
        #expect(model.menuBarHeaderLine == "Curfew at \(relockText)")
        #expect(model.upcomingCurfew == relock)
    }

    @Test("The glyph sinks toward curfew, rests on the line, and has no sun when locked")
    func glyphFollowsCurfew() {
        let model = makeTrustedModel()
        model.started = true
        let lock = Date(timeIntervalSince1970: 1_800_000_000)
        let unlock = lock.addingTimeInterval(13 * 3600)
        model.state = CurfewEvaluation(
            phase: .working, warningStage: .none, minutesRemaining: 150,
            canRequestExtension: false, lockDate: lock, unlockDate: unlock
        )
        model.currentTime = lock.addingTimeInterval(-150 * 60)
        #expect(model.menuBarGlyphState == .working(minutesToCurfew: 150))
        #expect(model.menuBarAccessibilityLabel.hasSuffix("2 hours, 30 minutes left"))
        model.currentTime = lock.addingTimeInterval(-20 * 60)
        #expect(model.menuBarGlyphState == .lastHalfHour)
        model.currentTime = lock.addingTimeInterval(60)
        model.state = .locked(lockDate: lock, unlockDate: unlock)
        #expect(model.menuBarGlyphState == .locked)
        #expect(HorizonMenuBarGlyph(state: model.menuBarGlyphState).sunCenter == nil)
    }

    @Test("No string promises an implementation-worded extension")
    func extensionTitleIsTheButton() {
        let model = makeTrustedModel()
        #expect(model.extensionRequestTitle == "15 more minutes")
    }

    @Test("A queued later curfew says when it starts and that the old one stands")
    func pendingWeakerScheduleCopy() throws {
        let model = makeTrustedModel()
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 17
        components.hour = 9
        let effective = try #require(Calendar.current.date(from: components))
        model.settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: .standardNineToFive,
            requestedAt: effective.addingTimeInterval(-86400),
            effectiveAt: effective, classification: .weaker
        )
        let day = effective.formatted(.dateTime.month(.abbreviated).day())
        #expect(model.pendingScheduleDescription ==
            "Your later curfew starts \(day). Until then, the old one stands.")
    }

    @Test("Menu bar countdown uses h:mm formatting and day-off placeholder")
    func timeRemainingTextFormatting() {
        let model = makeTestAppModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 125,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "2:05")

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "—")
    }

    /// Builds a `CurfewAppModel` over isolated defaults and a trusted
    /// ``FakeAccessibilityAuthorization`` so `enforcementHealth` seeds to
    /// `.active`, letting the per-phase menu-bar glyph show through.
    private func makeTrustedModel() -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }
}
