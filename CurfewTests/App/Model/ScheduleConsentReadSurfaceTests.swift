@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct ScheduleConsentReadSurfaceTests {
    @Test("Shortcuts reports a fresh remote lock even with weekly scheduling off")
    func intentReportsObservedRemoteLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-intent-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurfewObservedStatusStore(fileURL: directory
            .appendingPathComponent("status.json"))
        let now = Date()
        try store.save(CurfewObservedStatus(
            evaluation: .locked(
                lockDate: now.addingTimeInterval(-60),
                unlockDate: now.addingTimeInterval(240)
            ),
            observedAt: now,
            enforcementRunning: true,
            ownsLockout: true
        ))

        let status = CurfewIntentSupport.currentObservedStatus(at: now, store: store)

        #expect(status?.phase == "locked")
        #expect(CurfewIntentSupport.statusSummary(status).contains("Curfew is active"))
        #expect(CurfewIntentSupport.currentObservedStatus(
            at: now.addingTimeInterval(120), store: store
        ) == nil)
        #expect(CurfewIntentSupport.statusSummary(nil).contains("not reported"))
    }

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
