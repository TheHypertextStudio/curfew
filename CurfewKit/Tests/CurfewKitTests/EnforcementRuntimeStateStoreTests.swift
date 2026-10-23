@testable import CurfewKit
import Foundation
import Testing

struct EnforcementRuntimeStateStoreTests {
    @Test("Runtime state survives a fresh store instance")
    func reloadsGrantsAndBudgets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let state = EnforcementRuntimeState(
            dayToken: "2026-5-28", extensionMinutes: 30, snoozeMinutes: 2,
            extensionUses: 2, overrideUses: 1,
            extensionResetBoundary: now, overrideResetBoundary: now,
            overrideUntil: now.addingTimeInterval(1800)
        )
        try EnforcementRuntimeStateStore(recordURL: url).save(state)
        #expect(try EnforcementRuntimeStateStore(recordURL: url).load() == state)
    }

    @Test("Corrupt runtime state throws instead of looking like first launch")
    func corruptStoreIsExplicit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        #expect(throws: (any Error).self) { try EnforcementRuntimeStateStore(recordURL: url).load()
        }
    }

    @Test("Default runtime stores stay isolated in memory")
    func defaultStoresAreEphemeral() throws {
        let first = EnforcementRuntimeStateStore()
        try first.save(EnforcementRuntimeState(dayToken: "2026-5-28"))
        #expect(try first.load() != nil)
        #expect(try EnforcementRuntimeStateStore().load() == nil)
    }

    @Test("A failed replacement leaves the prior durable state intact")
    func writeFailureDoesNotEraseState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let original = EnforcementRuntimeState(dayToken: "2026-5-28", extensionUses: 2)
        let store = EnforcementRuntimeStateStore(recordURL: url)
        try store.save(original)
        let blockedStore = EnforcementRuntimeStateStore(recordURL: url
            .appendingPathComponent("invalid"))
        #expect(throws: (any Error).self) { try blockedStore.load() }
        #expect(throws: (any Error).self) { try blockedStore.save(original) }
        #expect(try store.load() == original)
    }

    @Test("Budget restoration retains uses above a temporarily lowered limit")
    func rebaseDoesNotForgetConsumption() {
        let now = Date()
        let lower = ExtensionBudgetTracker(
            weeklyLimit: 1, extensionMinutes: 15, resetWeekday: .monday,
            seedLastResetBoundary: now, seedUsedCount: 3
        )
        #expect(lower.remaining == 0)
        let higher = ExtensionBudgetTracker(
            weeklyLimit: 4, extensionMinutes: 15, resetWeekday: .monday,
            seedLastResetBoundary: lower.lastResetBoundary, seedUsedCount: lower.usedCount
        )
        #expect(higher.remaining == 1)
    }
}
