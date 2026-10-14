@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct ScheduleConsentReadSurfaceTests {
    @Test("Shortcuts evaluates the active consent state rather than the saved rule")
    func intentDoesNotPredictAnInactiveLock() throws {
        let suiteName = "CurfewSettingsStoreTests.IntentConsent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        let calendar = Calendar.current
        let lockTime = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 22
        )))

        let inactive = CurfewIntentSupport.currentEvaluation(
            at: lockTime,
            settingsStore: store,
            flavor: .studioDevelopment
        )
        #expect(inactive.phase == .dayOff)

        store.saveAutomaticScheduleConsent(true)
        let active = CurfewIntentSupport.currentEvaluation(
            at: lockTime,
            settingsStore: store,
            flavor: .studioDevelopment
        )
        #expect(active.phase == .locked)
    }
}
