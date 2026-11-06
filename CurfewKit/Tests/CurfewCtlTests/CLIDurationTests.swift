@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct CLIDurationTests {
    @Test("Status and activity JSON express durations in seconds")
    func recordedDurations() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let observation = CurfewObservedStatus(
            evaluation: CurfewEvaluation(
                phase: .warning,
                warningStage: .twoMinutes,
                minutesRemaining: 2,
                canRequestExtension: false,
                lockDate: now.addingTimeInterval(120),
                unlockDate: nil
            ),
            observedAt: now, enforcementRunning: true, ownsLockout: true
        )
        let status = try StatusCommand.jsonObject(from: observation)
        #expect(status["remaining_seconds"] as? Int == 120)
        #expect(status["minutes_remaining"] == nil)
        let event = ActivityEvent(
            timestamp: now,
            gateKind: GateKind.curfew,
            kind: .extensionGranted,
            minutesValue: 5,
            note: nil
        )
        let object = try #require(JSONSerialization
            .jsonObject(with: ActivityCommand.jsonData(events: [event])) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.first?["seconds"] as? Int == 300)
        #expect(events.first?["minutes"] == nil)
    }

    @Test("Budget JSON expresses grant durations in seconds")
    func budgetDurations() throws {
        var settings = CurfewSettings.default
        settings.extensionDurationMinutes = 5
        settings.overrideDurationMinutes = 10
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(dayToken: "2026-11-03"))
        let object = try BudgetCommand.snapshot(
            settings: settings,
            store: store,
            now: Date(),
            calendar: .current
        )
        let extensions = try #require(object["extensions"] as? [String: Int])
        let overrides = try #require(object["overrides"] as? [String: Int])
        #expect(extensions["duration_seconds"] == 300)
        #expect(overrides["duration_seconds"] == 600)
        #expect(extensions["duration_minutes"] == nil)
    }

    @Test("An invalid saved duration fails instead of overflowing")
    func overflowingDuration() {
        let event = ActivityEvent(
            timestamp: Date(),
            gateKind: GateKind.curfew,
            kind: .extensionGranted,
            minutesValue: Int.max,
            note: nil
        )
        #expect(throws: (any Error).self) { try ActivityCommand.jsonData(events: [event]) }
    }
}
