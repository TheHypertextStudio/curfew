@testable import CurfewKit
import Foundation
import Testing

struct LocalScheduleJournalTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The saved cooldown and receipt survive reopening before preferences are mirrored")
    func durableRequest() throws {
        try withStore { store, url, defaults in
            let old = store.load()
            try store.prepareScheduleRecovery(queue: MCPRequestQueueStore())
            var changed = old
            changed.pendingScheduleChange = PendingScheduleChange(
                proposedSchedule: .startupHours, requestedAt: now,
                effectiveAt: now.addingTimeInterval(86400), classification: .weaker
            )
            let request = scheduleRequest()
            try store.commitSchedule(changed, replacing: old, request: request, at: now)
            let reopened = CurfewSettingsStore(defaults: defaults, scheduleRecordURL: url)
            #expect(try reopened.loadChecked().pendingScheduleChange == changed
                .pendingScheduleChange)
            let outcome = try #require(try reopened.recoverScheduleOutcome(
                for: request, now: now.addingTimeInterval(120)
            ))
            #expect(outcome.status == .approved)
            #expect(outcome.resolvedAt == now)
            #expect(try reopened.scheduleRecoveryIDs() == [request.id])

            var userEdit = changed
            userEdit.schedule = .standardNineToFive
            userEdit.pendingScheduleChange = nil
            try reopened.commitSchedule(userEdit, replacing: changed, request: nil, at: now)
            try reopened.acknowledgeScheduleOutcome(outcome)
            #expect(try store.loadChecked().schedule == userEdit.schedule)
            #expect(try store.loadChecked().pendingScheduleChange == nil)
            #expect(try store.scheduleRecoveryIDs().isEmpty)
        }
    }

    @Test("Migration preserves existing settings and snapshots only the old pending schedule IDs")
    func migrateLegacyRequests() throws {
        try withStore { store, _, _ in
            let queue = MCPRequestQueueStore()
            let legacy = scheduleRequest()
            try queue.append(legacy)
            try queue.append(MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}"))
            let settings = store.load()
            try store.prepareScheduleRecovery(queue: queue)
            let fresh = scheduleRequest()
            try queue.append(fresh)
            try store.prepareScheduleRecovery(queue: queue)
            #expect(try store.loadChecked() == settings)
            #expect(try store.scheduleRecoveryIDs() == [legacy.id])
            #expect(try store.recoverScheduleOutcome(for: legacy, now: now)?.status == .denied)
            #expect(try store.recoverScheduleOutcome(for: fresh, now: now) == nil)
        }
    }

    @Test("A stale edit or conflicting request cannot replace the saved schedule")
    func rejectStaleAndConflictingWrites() throws {
        try withStore { store, url, defaults in
            try store.prepareScheduleRecovery(queue: MCPRequestQueueStore())
            let previous = store.load()
            let request = scheduleRequest()
            var next = previous
            next.schedule = .startupHours
            try store.commitSchedule(next, replacing: previous, request: request, at: now)
            let before = try Data(contentsOf: url)
            let second = CurfewSettingsStore(defaults: defaults, scheduleRecordURL: url)
            #expect(throws: (any Error).self) {
                try second.commitSchedule(previous, replacing: previous, request: nil, at: now)
            }
            let conflict = MCPPendingRequest(
                id: request.id,
                tool: .setSchedule,
                argumentsJSON: "{}"
            )
            #expect(throws: MCPRequestQueueError.conflictingIdentity) {
                _ = try second.recoverScheduleOutcome(for: conflict, now: now)
            }
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("A corrupt or removed authority cannot be silently replaced by a stale edit")
    func preserveDamagedState() throws {
        try withStore { store, url, _ in
            try store.prepareScheduleRecovery(queue: MCPRequestQueueStore())
            let settings = store.load()
            let corrupt = Data("invalid".utf8)
            try corrupt.write(to: url)
            #expect(throws: (any Error).self) { _ = try store.loadChecked() }
            #expect(throws: (any Error).self) {
                try store.commitSchedule(settings, replacing: settings, request: nil, at: now)
            }
            #expect(try Data(contentsOf: url) == corrupt)
            try FileManager.default.removeItem(at: url)
            #expect(throws: (any Error).self) {
                try store.commitSchedule(settings, replacing: settings, request: nil, at: now)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    private func scheduleRequest() -> MCPPendingRequest {
        MCPPendingRequest(
            tool: .setSchedule,
            argumentsJSON: #"{"weekday":"monday","lock_time":"22:00"}"#
        )
    }

    private func withStore(_ body: (CurfewSettingsStore, URL, UserDefaults) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let suite = "CurfewScheduleJournal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("schedule.json")
        let store = CurfewSettingsStore(defaults: defaults, scheduleRecordURL: url)
        var settings = CurfewSettings.default
        settings.schedule = .allDaysOff
        store.save(settings)
        try body(store, url, defaults)
    }
}
