@testable import Curfew
import CoreServices
import CurfewKit
import Testing

struct SettingsCopyTests {
    @Test("Warning summary lists every stage in plain words")
    func warningSummary() {
        let summary = SettingsCopy.warningSummary(.default)
        #expect(summary.hasPrefix("Curfew warns you "))
        #expect(summary.hasSuffix(" minutes before curfew."))
        #expect(summary.contains(" and "))
        #expect(!summary.contains("lockout"))
    }

    @Test("Automation answers map to granted, denied or undecided")
    func automationResult() {
        #expect(ShutdownAutomationPermission.result(for: noErr) == .granted)
        #expect(ShutdownAutomationPermission.result(for: OSStatus(errAEEventNotPermitted)) == .denied)
        #expect(ShutdownAutomationPermission.result(for: OSStatus(procNotFound)) == .undetermined)
    }

    @Test("Settings sidebar uses sentence case and no implementation words")
    func sidebarTitles() {
        for section in SettingsSection.allCases {
            let title = section.title
            let rest = title.dropFirst()
            #expect(rest == rest.lowercased(), "\(title)")
            #expect(!title.lowercased().contains("lockout"))
        }
    }

    @Test("Developer detail stays out of the production flavor")
    func developerDetail() {
        #expect(!SettingsDeveloperDetail.resolve(flavor: .production, environment: [:]))
        #expect(SettingsDeveloperDetail.resolve(flavor: .development, environment: [:]))
        #expect(SettingsDeveloperDetail.resolve(
            flavor: .production, environment: ["CURFEW_DIAGNOSTICS": "1"]
        ))
    }
}

struct ScheduleLockRuleTests {
    @Test("The week's lock rule reads from working days and notices differences")
    func currentRule() {
        var schedule = WeeklySchedule.tenToSix
        #expect(ScheduleLockRule.current(in: schedule).mode == .time)
        #expect(!ScheduleLockRule.current(in: schedule).isMixed)
        schedule.rules[.tuesday] = DayRule(
            isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 8 * 60,
            mode: .hours, hoursLimitMinutes: 7 * 60
        )
        #expect(ScheduleLockRule.current(in: schedule).isMixed)
    }

    @Test("Work limits read as hours and minutes")
    func hoursText() {
        #expect(ScheduleLockRule.hoursText(8) == "8 hours")
        #expect(ScheduleLockRule.hoursText(1) == "1 hour")
        #expect(ScheduleLockRule.hoursText(7.5) == "7 hours 30 minutes")
    }
}

struct ReflectionPromptsCopyTests {
    @Test("Restoring defaults says what will be lost before it happens")
    func restoreConfirmation() {
        #expect(ReflectionPromptsCopy.restoreButton.hasSuffix("…"))
        #expect(ReflectionPromptsCopy.restoreMessage.contains("replaced"))
        #expect(ReflectionPromptsCopy.restoreMessage.contains("can't be undone"))
    }

    @Test("Question editor names Sunrise and curfew, not work sessions or lockout")
    func vocabulary() {
        let all = [
            ReflectionPromptsCopy.gatesSubtitle, ReflectionPromptsCopy.sunriseTitle,
            ReflectionPromptsCopy.sunriseSubtitle, ReflectionPromptsCopy.curfewTitle,
            ReflectionPromptsCopy.curfewSubtitle
        ]
        for line in all {
            #expect(!line.lowercased().contains("lockout"), "\(line)")
            #expect(!line.lowercased().contains("session"), "\(line)")
        }
    }
}
