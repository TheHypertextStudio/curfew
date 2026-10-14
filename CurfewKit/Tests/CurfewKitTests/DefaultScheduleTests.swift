@testable import CurfewKit
import Foundation
import Testing

struct NewInstallScheduleTests {
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
