@testable import CurfewKit
import Foundation
import Testing

/// Raising a weekly limit waits exactly as loosening the schedule does;
/// lowering one applies at once. These are the pure rules; the app model
/// tests cover the tick loop and every reader.
struct WeeklyLimitPolicyTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let engine = SchedulePolicyEngine(calendar: Self.utc)
    private var policy: WeeklyLimitPolicy {
        WeeklyLimitPolicy(engine: engine)
    }

    /// Monday 16 November 2026, 17:55 UTC: five minutes before a 6 PM curfew.
    private let requestedAt = Date(timeIntervalSince1970: 1_794_851_700)

    private func configured() -> CurfewSettings {
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.extensionWeeklyLimit = 3
        settings.extensionDurationMinutes = 15
        settings.overrideWeeklyLimit = 2
        settings.overrideDurationMinutes = 30
        return settings
    }

    // MARK: - Raise waits, lower applies

    @Test("Raising any limit leaves the value in force and queues the raise", arguments: [
        (WeeklyLimit.extensionCount, 20),
        (WeeklyLimit.extensionMinutes, 60),
        (WeeklyLimit.overrideCount, 10),
        (WeeklyLimit.overrideMinutes, 480)
    ])
    func raiseWaits(limit: WeeklyLimit, value: Int) throws {
        let before = configured()
        let after = policy.request(limit, value: value, in: before, at: requestedAt)
        #expect(after[limit] == before[limit])
        let pending = try #require(after.pendingLimitChange(for: limit))
        #expect(pending.value == value)
        #expect(pending.requestedAt == requestedAt)
        #expect(pending.effectiveAt == requestedAt.addingTimeInterval(24 * 60 * 60))
        #expect(after.requestedLimit(limit) == value)
        for other in WeeklyLimit.allCases where other != limit {
            #expect(after[other] == before[other])
            #expect(after.pendingLimitChange(for: other) == nil)
        }
    }

    @Test("A raise takes effect at the same moment a loosened schedule would")
    func sameBoundaryAsSchedule() throws {
        let after = policy.request(.overrideCount, value: 9, in: configured(), at: requestedAt)
        let pending = try #require(after.pendingLimitChange(for: .overrideCount))
        #expect(pending.effectiveAt == engine.earliestEffectiveDate(
            for: .weaker, requestedAt: requestedAt
        ))
        #expect(policy.classify(from: 2, to: 9) == .weaker)
        #expect(policy.classify(from: 9, to: 2) == .stricter)
        #expect(policy.classify(from: 2, to: 2) == .noChange)
    }

    @Test("Lowering a limit applies at once", arguments: WeeklyLimit.allCases)
    func lowerApplies(limit: WeeklyLimit) {
        let before = configured()
        let lower = before[limit] - 1
        let after = policy.request(limit, value: lower, in: before, at: requestedAt)
        #expect(after[limit] == lower)
        #expect(after.pendingLimitChange(for: limit) == nil)
    }

    @Test("Lowering below the value in force applies at once and clears a waiting raise")
    func lowerClearsPendingRaise() {
        let raised = policy.request(.extensionCount, value: 20, in: configured(), at: requestedAt)
        let lowered = policy.request(
            .extensionCount, value: 1, in: raised, at: requestedAt.addingTimeInterval(60)
        )
        #expect(lowered.extensionWeeklyLimit == 1)
        #expect(lowered.pendingLimitChange(for: .extensionCount) == nil)
        #expect(lowered.pendingLimitChanges.isEmpty)
    }

    // MARK: - Replace and cancel

    @Test("Raising a waiting value further replaces it and starts the wait again")
    func raiseAgainReplaces() throws {
        let first = policy.request(.extensionCount, value: 5, in: configured(), at: requestedAt)
        let later = requestedAt.addingTimeInterval(3600)
        let second = policy.request(.extensionCount, value: 8, in: first, at: later)
        #expect(second.pendingLimitChanges.count == 1)
        let pending = try #require(second.pendingLimitChange(for: .extensionCount))
        #expect(pending.value == 8)
        #expect(pending.requestedAt == later)
        #expect(pending.effectiveAt == later.addingTimeInterval(24 * 60 * 60))
        #expect(second.extensionWeeklyLimit == 3)
    }

    @Test("Shrinking a waiting raise keeps its original time, since it asks for less")
    func shrinkKeepsTime() throws {
        let first = policy.request(.extensionCount, value: 8, in: configured(), at: requestedAt)
        let second = policy.request(
            .extensionCount, value: 5, in: first, at: requestedAt.addingTimeInterval(3600)
        )
        let pending = try #require(second.pendingLimitChange(for: .extensionCount))
        #expect(pending.value == 5)
        #expect(pending.requestedAt == requestedAt)
        #expect(pending.effectiveAt == requestedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test("Setting a waiting value back to the value in force cancels it")
    func setBackCancels() {
        let raised = policy.request(.overrideMinutes, value: 60, in: configured(), at: requestedAt)
        let cancelled = policy.request(.overrideMinutes, value: 30, in: raised, at: requestedAt)
        #expect(cancelled.overrideDurationMinutes == 30)
        #expect(cancelled.pendingLimitChange(for: .overrideMinutes) == nil)
        #expect(cancelled == configured())
    }

    @Test("Each limit waits on its own")
    func independentLimits() {
        var settings = policy.request(.extensionCount, value: 6, in: configured(), at: requestedAt)
        settings = policy.request(
            .overrideCount, value: 4, in: settings, at: requestedAt.addingTimeInterval(7200)
        )
        settings = policy.request(.extensionMinutes, value: 5, in: settings, at: requestedAt)
        #expect(settings.pendingLimitChanges.map(\.limit) == [.extensionCount, .overrideCount])
        #expect(settings.extensionDurationMinutes == 5)
        #expect(settings.pendingLimitChange(for: .extensionCount)?.effectiveAt ==
            requestedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test("Before setup is finished a raise applies at once, as a schedule edit does")
    func beforeSetupApplies() {
        var settings = configured()
        settings.hasCompletedInitialSetup = false
        let after = policy.request(.extensionCount, value: 7, in: settings, at: requestedAt)
        #expect(after.extensionWeeklyLimit == 7)
        #expect(after.pendingLimitChanges.isEmpty)
    }

    // MARK: - Applying

    @Test("A waiting raise applies once its time arrives, not a second before")
    func appliesOnTime() {
        let raised = policy.request(.overrideCount, value: 9, in: configured(), at: requestedAt)
        let effectiveAt = requestedAt.addingTimeInterval(24 * 60 * 60)

        let early = policy.applyDue(
            in: raised,
            at: effectiveAt.addingTimeInterval(-1),
            isLocked: false
        )
        #expect(early.settings == raised)
        #expect(early.applied.isEmpty)

        let due = policy.applyDue(in: raised, at: effectiveAt, isLocked: false)
        #expect(due.settings.overrideWeeklyLimit == 9)
        #expect(due.settings.pendingLimitChanges.isEmpty)
        #expect(due.applied.map(\.limit) == [.overrideCount])
    }

    @Test("A due raise is held while this Mac is locked, as a looser schedule is")
    func heldWhileLocked() {
        let raised = policy.request(.overrideCount, value: 9, in: configured(), at: requestedAt)
        let later = requestedAt.addingTimeInterval(48 * 60 * 60)
        let held = policy.applyDue(in: raised, at: later, isLocked: true)
        #expect(held.settings == raised)
        #expect(held.applied.isEmpty)
        #expect(policy.applyDue(in: raised, at: later, isLocked: false).settings
            .overrideWeeklyLimit == 9)
    }

    @Test("Setting the clock back never brings a raise closer")
    func clockBackwards() throws {
        let raised = policy.request(.extensionCount, value: 10, in: configured(), at: requestedAt)
        let pending = try #require(raised.pendingLimitChange(for: .extensionCount))
        let past = requestedAt.addingTimeInterval(-7 * 24 * 60 * 60)
        let result = policy.applyDue(in: raised, at: past, isLocked: false)
        #expect(result.settings == raised)
        #expect(result.settings.pendingLimitChange(for: .extensionCount) == pending)
        // Editing again while the clock is wrong cannot pull the time in either.
        let edited = policy.request(.extensionCount, value: 10, in: raised, at: past)
        #expect(edited.pendingLimitChange(for: .extensionCount) == pending)
    }

    @Test("A stored raise that is no longer a raise is dropped, never applied")
    func staleEntryDropped() {
        var settings = configured()
        settings.pendingLimitChanges = [PendingLimitChange(
            limit: .extensionCount, value: 2,
            requestedAt: requestedAt, effectiveAt: requestedAt
        )]
        let result = policy.applyDue(in: settings, at: requestedAt, isLocked: false)
        #expect(result.settings.extensionWeeklyLimit == 3)
        #expect(result.settings.pendingLimitChanges.isEmpty)
        #expect(result.applied.isEmpty)
    }

    // MARK: - Synced settings

    @Test("A raised limit arriving from another Mac waits here too")
    func remoteRaiseWaits() throws {
        let local = configured()
        var remote = local
        remote.extensionWeeklyLimit = 20
        let merged = policy.gateRemote(remote, local: local, at: requestedAt)
        #expect(merged.extensionWeeklyLimit == 3)
        let pending = try #require(merged.pendingLimitChange(for: .extensionCount))
        #expect(pending.value == 20)
        #expect(pending.effectiveAt == requestedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test("A waiting raise from another Mac cannot carry an earlier time")
    func remoteCannotBackdate() throws {
        let local = configured()
        var remote = local
        remote.pendingLimitChanges = [PendingLimitChange(
            limit: .overrideMinutes, value: 480,
            requestedAt: .distantPast, effectiveAt: .distantPast
        )]
        let merged = policy.gateRemote(remote, local: local, at: requestedAt)
        #expect(merged.overrideDurationMinutes == 30)
        let pending = try #require(merged.pendingLimitChange(for: .overrideMinutes))
        #expect(pending.effectiveAt == requestedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test("Our own waiting raise echoed back by sync keeps its time")
    func echoKeepsTime() throws {
        let local = policy.request(.overrideCount, value: 5, in: configured(), at: requestedAt)
        let merged = policy.gateRemote(
            local, local: local, at: requestedAt.addingTimeInterval(20 * 60 * 60)
        )
        #expect(merged == local)
        #expect(try #require(merged.pendingLimitChange(for: .overrideCount)).effectiveAt ==
            requestedAt.addingTimeInterval(24 * 60 * 60))
    }

    @Test("A lower limit from another Mac applies at once")
    func remoteLowerApplies() {
        let local = policy.request(.extensionCount, value: 9, in: configured(), at: requestedAt)
        var remote = configured()
        remote.extensionWeeklyLimit = 1
        let merged = policy.gateRemote(remote, local: local, at: requestedAt)
        #expect(merged.extensionWeeklyLimit == 1)
        #expect(merged.pendingLimitChanges.isEmpty)
    }

    // MARK: - Persistence

    @Test("A waiting raise survives encoding")
    func roundTrip() throws {
        let raised = policy.request(.overrideCount, value: 9, in: configured(), at: requestedAt)
        let data = try JSONEncoder().encode(raised)
        #expect(try JSONDecoder().decode(CurfewSettings.self, from: data) == raised)
    }

    @Test("Settings saved before this change load unchanged, with nothing waiting")
    func legacyPayload() throws {
        let saved = configured()
        let data = try JSONEncoder().encode(saved)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "pendingLimitChanges")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let loaded = try JSONDecoder().decode(CurfewSettings.self, from: legacy)
        #expect(loaded == saved)
        #expect(loaded.pendingLimitChanges.isEmpty)
        for limit in WeeklyLimit.allCases {
            #expect(loaded.requestedLimit(limit) == saved[limit])
        }
    }

    @Test("A store round trip keeps the value in force and the waiting raise")
    func storeRelaunch() throws {
        let suite = "WeeklyLimitPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let raised = policy.request(.extensionCount, value: 9, in: configured(), at: requestedAt)
        CurfewSettingsStore(defaults: defaults).save(raised)
        let reloaded = CurfewSettingsStore(defaults: defaults).load()
        #expect(reloaded.extensionWeeklyLimit == 3)
        #expect(reloaded.pendingLimitChange(for: .extensionCount)?.value == 9)
        #expect(reloaded.pendingLimitChange(for: .extensionCount)?.effectiveAt ==
            requestedAt.addingTimeInterval(24 * 60 * 60))
    }
}
