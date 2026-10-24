@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct RuntimeRestartTests {
    @Test("Lowering then raising the weekly limit preserves every prior use")
    func lowerThenRaisePreservesUsage() {
        let model = ModelTestSupport.makeModel()
        model.currentTime = Date()
        for _ in 0 ..< 3 {
            _ = model.extensionTracker.requestExtension(at: model.currentTime)
        }
        model.extensionsRemaining = model.extensionTracker.remaining
        model.settings.extensionWeeklyLimit = 1
        model.settings.extensionWeeklyLimit = 4
        #expect(model.extensionsRemaining == 1)
    }

    @Test("A fresh model restores daily grants and override before evaluation")
    func restartRestoresBeforeEvaluation() throws {
        let now = Date()
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(
            dayToken: CurfewAppModel.dayToken(for: now),
            extensionMinutes: 30, snoozeMinutes: 2, extensionUses: 2, overrideUses: 1,
            extensionResetBoundary: now, overrideResetBoundary: now,
            overrideUntil: now.addingTimeInterval(1800)
        ))
        let model = makeModel(store: store, now: now, enforcementEnabled: true)
        #expect(model.extensionMinutesGrantedToday == 30)
        #expect(model.snoozeMinutesGrantedToday == 2)
        #expect(model.extensionsRemaining == 1)
        #expect(model.overridesRemaining == 1)
        #expect(model.overrideUntil == now.addingTimeInterval(1800))
        #expect(model.state.phase == .working)
    }

    @Test("Restart after midnight discards daily grants but retains weekly consumption")
    func nextDayKeepsWeeklyConsumption() throws {
        let now = Date()
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(
            dayToken: "2000-1-1", extensionMinutes: 30, snoozeMinutes: 2,
            extensionUses: 2, overrideUses: 1,
            extensionResetBoundary: now, overrideResetBoundary: now
        ))
        let model = makeModel(store: store, now: now)
        #expect(model.extensionMinutesGrantedToday == 0)
        #expect(model.snoozeMinutesGrantedToday == 0)
        #expect(model.extensionsRemaining == 1)
        #expect(model.overridesRemaining == 1)
    }

    @Test("Extension, snooze, and override writes survive a fresh process model")
    func grantsPersistBeforeReturning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let model = makeModel(store: EnforcementRuntimeStateStore(recordURL: url))
        model.state = warningState()
        model.confirmExtensionRequest()
        #expect(try EnforcementRuntimeStateStore(recordURL: url).load()?.extensionUses == 1)
        model.state = warningState()
        model.requestNotificationSnooze()
        #expect(try EnforcementRuntimeStateStore(recordURL: url).load()?.snoozeMinutes == 1)
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .lockout, minutesRemaining: 0,
            canRequestExtension: false, lockDate: nil, unlockDate: nil
        )
        model.overrideReasonDraft = String(repeating: "r", count: 50)
        model.overrideRequestedAt = model.currentTime
            .addingTimeInterval(-OverrideRequestPolicy.cooldownSeconds)
        #expect(model.canConfirmOverride)
        model.confirmOverride()
        let restarted = makeModel(store: EnforcementRuntimeStateStore(recordURL: url))
        #expect(restarted.extensionMinutesGrantedToday == 15)
        #expect(restarted.snoozeMinutesGrantedToday == 1)
        #expect(restarted.extensionsRemaining == 2)
        #expect(restarted.overridesRemaining == 1)
        #expect(restarted.overrideUntil == model.overrideUntil)
    }

    @Test("An unwritable state file prevents a grant from changing the deadline or budget")
    func failedWriteRejectsGrant() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let model = makeModel(store: EnforcementRuntimeStateStore(recordURL: url))
        try FileManager.default.removeItem(at: directory)
        try Data("blocks the parent path".utf8).write(to: directory)
        model.state = warningState()
        model.confirmExtensionRequest()
        #expect(model.extensionsRemaining == 3)
        #expect(model.extensionMinutesGrantedToday == 0)
        #expect(model.runtimePersistenceError != nil)
    }

    @Test("A corrupt state file exhausts grants and stays available for recovery")
    func corruptRuntimeDoesNotReplenishBudget() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let broken = Data("broken".utf8)
        try broken.write(to: url)
        let model = makeModel(store: EnforcementRuntimeStateStore(recordURL: url))
        #expect(model.extensionsRemaining == 0)
        #expect(model.overridesRemaining == 0)
        #expect(model.runtimePersistenceError != nil)
        model.state = warningState()
        model.confirmExtensionRequest()
        model.requestNotificationSnooze()
        #expect(model.extensionMinutesGrantedToday == 0)
        #expect(model.snoozeMinutesGrantedToday == 0)
        #expect(try Data(contentsOf: url) == broken)
    }

    @Test("First runtime snapshot migrates local extension and override history once")
    func migrationDoesNotDoubleCountHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let activityStore = try ActivityStore(databaseURL: directory
            .appendingPathComponent("activity.sqlite3"))
        let recorder = ActivityRecorder(store: activityStore)
        recorder.recordExtensionGranted(minutes: 15, at: now.addingTimeInterval(-30))
        let suite = "CurfewRuntimeMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settingsStore = CurfewSettingsStore(defaults: defaults)
        settingsStore.appendOverrideEvent(OverrideEvent(
            timestamp: now.addingTimeInterval(-10), deviceName: "Test Mac",
            reason: String(repeating: "r", count: 50), grantedDurationMinutes: 30
        ))
        let url = directory.appendingPathComponent("runtime.json")
        let initial = makeModel(
            store: EnforcementRuntimeStateStore(recordURL: url), now: now,
            settingsStore: settingsStore, recorder: recorder
        )
        let restarted = makeModel(
            store: EnforcementRuntimeStateStore(recordURL: url), now: now,
            settingsStore: settingsStore, recorder: recorder
        )
        #expect(initial.extensionsRemaining == 2)
        #expect(restarted.extensionsRemaining == 2)
        #expect(restarted.overridesRemaining == 1)
        #expect(restarted.overrideUntil == now.addingTimeInterval(1790))
        #expect(restarted.extensionMinutesGrantedToday == 15)
    }

    private func makeModel(
        store: EnforcementRuntimeStateStore,
        now: Date = Date(),
        settingsStore: CurfewSettingsStore? = nil,
        recorder: (any ActivityRecording)? = nil,
        enforcementEnabled: Bool = false
    ) -> CurfewAppModel {
        let defaults = UserDefaults(suiteName: "CurfewRuntimeTests.\(UUID().uuidString)")!
        let settingsStore = settingsStore ?? CurfewSettingsStore(defaults: defaults)
        var settings = settingsStore.load()
        settings.hasCompletedInitialSetup = enforcementEnabled
        for weekday in Weekday.allCases {
            settings.schedule.rules[weekday] = DayRule(
                isDayOff: !enforcementEnabled, lockMinutes: 0, unlockMinutes: 23 * 60 + 59
            )
        }
        settingsStore.save(settings)
        settingsStore.saveAutomaticScheduleConsent(enforcementEnabled)
        return CurfewAppModel(
            settingsStore: settingsStore,
            appRouter: AppRouterSpy(),
            activityRecorder: recorder ?? NullActivityRecording(),
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            runtimeStateStore: store, runtimeNow: now
        )
    }

    private func warningState() -> CurfewEvaluation {
        CurfewEvaluation(
            phase: .warning, warningStage: .fifteenMinutes, minutesRemaining: 15,
            canRequestExtension: true, lockDate: nil, unlockDate: nil
        )
    }
}
