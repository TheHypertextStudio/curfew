@testable import CurfewKit
import Foundation
import Testing

struct NewInstallScheduleTests {
    @Test(
        "Fresh local settings cross the 22:00 and 06:00 enforcement boundaries",
        arguments: [false, true]
    )
    func freshInstallOvernightBoundary(corruptSettings: Bool) throws {
        let suiteName = "CurfewSettingsStoreTests.DefaultBoundary.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        if corruptSettings {
            defaults.set(Data("invalid settings".utf8), forKey: "curfew.settings.v1")
        }
        let schedule = CurfewSettingsStore(defaults: defaults).load().schedule
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let engine = CurfewEnforcementEngine(calendar: calendar)
        let cases: [(day: Int, hour: Int, minute: Int, phase: EnforcementPhase)] = [
            (13, 18, 0, .working),
            (13, 21, 59, .warning),
            (13, 22, 0, .locked),
            (14, 5, 59, .locked),
            (14, 6, 0, .working)
        ]

        for sample in cases {
            let date = try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 10,
                day: sample.day,
                hour: sample.hour,
                minute: sample.minute
            )))
            let evaluation = engine.evaluate(
                at: date,
                schedule: schedule,
                extensionMinutesGrantedToday: 0,
                overrideUntil: nil
            )
            #expect(evaluation.phase == sample.phase)
        }
    }

    @Test("A fresh install proposes 22:00 to 06:00 on weekdays")
    func freshInstallProposesTenToSix() {
        let schedule = CurfewSettings.default.schedule

        for weekday in Weekday.allCases where weekday != .saturday && weekday != .sunday {
            let rule = schedule.rule(for: weekday)
            #expect(!rule.isDayOff)
            #expect(rule.lockMinutes == 22 * 60)
            #expect(rule.unlockMinutes == 6 * 60)
        }
        #expect(schedule.rule(for: .saturday).isDayOff)
        #expect(schedule.rule(for: .sunday).isDayOff)
    }

    @Test("A saved custom schedule survives a default-value update")
    func existingSettingsRetainCustomSchedule() {
        let suiteName = "CurfewSettingsStoreTests.SavedSchedule.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated defaults.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.schedule = .startupHours
        store.save(settings)

        #expect(store.load().schedule == .startupHours)
    }
}
