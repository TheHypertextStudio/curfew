@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct LiteralCopyTests {
    @Test("Lockout messages do not assume work cannot resume later today")
    func lockoutMessagesDescribeTheCurrentWindow() {
        #expect(EncouragementMessageCatalog.messages == [
            "Curfew is blocking access.",
            "Lockout has started.",
            "Take time to rest.",
            "Rest well.",
            "Lockout is active."
        ])
    }

    @Test("Disabled Today copy describes Curfew rather than the system lock")
    func disabledTodayExplainsCurfew() {
        #expect(TodaySundownView()
            .statusDetail == "Curfew won't block access until you turn it on.")
    }

    @Test("Today distinguishes setup from enabled and disabled scheduling")
    func todayControlsDescribeScheduledEnforcement() {
        let enabled = TodayView.control(needsSetup: false, enforcing: true)
        #expect(enabled.line == "Curfew is on")
        #expect(enabled.detail == "Curfew is set to enforce your schedule.")
        #expect(enabled.action.isEmpty)
        let disabled = TodayView.control(needsSetup: false, enforcing: false)
        #expect(disabled.detail == "Curfew won't block access until you turn it on.")
        #expect(disabled.action == "Turn on Curfew")
        let setup = TodayView.control(needsSetup: true, enforcing: false)
        #expect(setup.detail == "Set your schedule, then turn Curfew on.")
        #expect(setup.action == "Finish Setup")
    }

    @Test("Presence reminder instructions distinguish idle detection from the extra delay")
    func presenceReminderExplainsBothIntervals() {
        let idleMinutes = Int(IdleWatcher.defaultIdleThresholdSeconds) / 60
        #expect(SettingsView.presenceNudgeNote.contains(
            "Curfew detects inactivity after \(idleMinutes) minutes without keyboard or pointer input."
        ))
        #expect(SettingsView.presenceNudgeNote.contains(
            "The additional delay starts when the camera detects a person "
                + "and Curfew detects inactivity."
        ))
    }

    @Test("Local assistant consent states readable data and lockout limits before the switch")
    func localAssistantSummaryNamesDataAndLimits() {
        #expect(SettingsView.localAIExplanation ==
            "While enabled, local assistants can read your Curfew status, schedule, activity, "
            + "and reflection text. They cannot end lockout or turn off Curfew.")
    }

    @Test("Presence introduction explains the camera and its limit in two sentences")
    func presenceIntroductionNamesTheCameraLimit() {
        #expect(SettingsView.presenceExplanation ==
            "Curfew uses the camera to estimate whether someone is at your Mac. "
            + "It cannot tell whether you're working.")
    }

    @Test("Presence copy distinguishes input inactivity from work")
    func presenceDescribesObservations() {
        #expect(SettingsView
            .presenceDescription(.presentButIdle) == "person detected, but no recent input")
        #expect(SettingsView
            .presenceDescription(.unknown) == "Curfew can't determine whether you're at your Mac.")
    }

    @Test("Notifications name lockout without assuming a morning unlock")
    func notificationsDescribeLockout() throws {
        let fifteen = try #require(WarningNotificationManager.payload(for: .fifteenMinutes))
        #expect(fifteen.body == "Lockout starts in 15 minutes. Finish your current task.")
        let lockout = try #require(WarningNotificationManager.payload(for: .lockout))
        #expect(lockout.body == "Lockout has started. Rest well.")
        #expect(WarningNotificationManager.distractionPayload.body
            ==
            "Curfew detected a person but no recent keyboard or pointer input. "
            + "Do you want to continue your task or take a break?")
    }

    @Test("Accessibility guidance names the unavailable capability")
    func healthDescribesShortcutBlocking() {
        #expect(EnforcementHealth.degradedNoAccessibility
            .bannerTitle == "Keyboard shortcut blocking is unavailable")
        #expect(EnforcementHealth.degradedTapDown
            .bannerTitle == "Keyboard shortcut blocking was interrupted")
        #expect(EnforcementHealth.active
            .settingsStatusTitle == "Keyboard shortcut blocking is available")
        #expect(EnforcementHealth.degradedNoAccessibility.bannerDetail?
            .contains("bypass shortcuts") == true)
    }

    @Test("Setup copy describes schedules without judging the user")
    func setupDescribesActions() {
        #expect(GettingStartedCopy
            .commitmentMessage ==
            "Choose your work hours. Curfew warns you before lockout "
            + "and blocks access when work ends.")
        #expect(ScheduleSurfaceCopy
            .onboardingMessage == "Choose when work ends and resumes each day.")
        #expect(ScheduleSurfaceCopy.weeklyScheduleSubtitle
            == "Set when work ends and when access resumes each day.")
        #expect(ScheduleSurfaceCopy.countdownPrefix == "until scheduled lockout at")
        #expect(FirstRunStep.confirmation.checklist == ["Review your schedule", "Enable Curfew"])
    }

    @Test("Shutdown countdown names shutdown rather than sleep")
    func countdownDescribesShutdown() {
        var workflow = ShutdownWorkflow()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: ShutdownControllerSpy(results: [])
        )
        #expect(workflow.statusLine(now: now) == "Your Mac will shut down in 10:00.")
    }

    @Test("Consent copy limits the approval promise to supported requests")
    func consentNamesTheRequests() {
        #expect(AIConsentPolicy.queue
            .rationale ==
            "Curfew asks before applying an AI-requested extension or schedule change.")
    }

    @Test("Default reflection questions describe work without judgment")
    func reflectionDefaultsStayNeutral() {
        #expect(ReflectionDefaults.morningPrompts[1]
            .text == "How prepared do you feel to start work?")
        #expect(ReflectionDefaults.eveningPrompts[0].text == "What did you finish today?")
        #expect(ReflectionDefaults.eveningPrompts[1]
            .text == "What would you like to continue next time?")
    }

    @Test("Deferral copy names a bounded shutdown delay")
    func deferralNamesShutdownDelay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let gate = ProtectedWorkDeferral()
        #expect(gate.statusLine(now: now, decision: .deferred(until: now.addingTimeInterval(300)))
            == "Protected work is running. Shutdown is delayed for up to 5 more min.")
    }
}
