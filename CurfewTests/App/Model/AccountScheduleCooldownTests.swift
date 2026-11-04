@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

@MainActor
final class AccountScheduleCooldownTests: XCTestCase {
    func testRepeatedScheduleRequestKeepsOriginalCooldown() throws {
        let suite = "Curfew.AccountScheduleCooldown.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            enforcementClock: { now }
        )
        model.currentTime = now
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes += 60

        model.queueScheduleUpdate(proposed)
        let first = try XCTUnwrap(model.settings.pendingScheduleChange)
        now = now.addingTimeInterval(600)
        model.currentTime = now
        model.queueScheduleUpdate(proposed)

        XCTAssertEqual(model.settings.pendingScheduleChange, first)
    }
}
