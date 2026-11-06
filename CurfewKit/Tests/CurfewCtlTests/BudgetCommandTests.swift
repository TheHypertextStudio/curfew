@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct BudgetCommandTests {
    @Test("Budget uses persisted grant counters rather than activity-history counts")
    func persistedAuthority() throws {
        var settings = CurfewSettings.default
        settings.extensionWeeklyLimit = 5
        settings.overrideWeeklyLimit = 3
        settings.resetWeekday = .wednesday
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(
            dayToken: "2026-11-02", extensionUses: 2, overrideUses: 1,
            extensionResetBoundary: budgetDate(month: 10, day: 28),
            overrideResetBoundary: budgetDate(month: 10, day: 28)
        ))
        let result = try BudgetCommand.snapshot(
            settings: settings,
            store: store,
            now: budgetDate(day: 2),
            calendar: budgetCalendar()
        )
        let extensions = try #require(result["extensions"] as? [String: Int])
        let overrides = try #require(result["overrides"] as? [String: Int])
        #expect(extensions["used"] == 2)
        #expect(extensions["remaining"] == 3)
        #expect(overrides["used"] == 1)
        #expect(overrides["remaining"] == 2)
    }

    @Test("Budget applies the configured weekly reset without writing runtime state")
    func authorityRollover() throws {
        var settings = CurfewSettings.default
        settings.resetWeekday = .wednesday
        let store = EnforcementRuntimeStateStore()
        let state = try EnforcementRuntimeState(
            dayToken: "2026-11-02", extensionUses: 2, overrideUses: 1,
            extensionResetBoundary: budgetDate(month: 10, day: 28),
            overrideResetBoundary: budgetDate(month: 10, day: 28)
        )
        try store.save(state)
        let result = try BudgetCommand.snapshot(
            settings: settings,
            store: store,
            now: budgetDate(day: 4, hour: 0),
            calendar: budgetCalendar()
        )
        let extensions = try #require(result["extensions"] as? [String: Int])
        let overrides = try #require(result["overrides"] as? [String: Int])
        #expect(extensions["used"] == 0)
        #expect(overrides["used"] == 0)
        #expect(try store.load() == state)
    }

    @Test("Budget preserves consumption carried across a reset-weekday edit")
    func rebasedReset() throws {
        var settings = CurfewSettings.default
        settings.resetWeekday = .friday
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(
            dayToken: "2026-11-02", extensionUses: 2,
            extensionResetBoundary: budgetDate(month: 10, day: 30)
        ))
        let result = try BudgetCommand.snapshot(
            settings: settings,
            store: store,
            now: budgetDate(day: 2),
            calendar: budgetCalendar()
        )
        let extensions = try #require(result["extensions"] as? [String: Int])
        #expect(extensions["used"] == 2)
    }

    @Test("A lower budget limit keeps consumed uses and clamps remaining to zero")
    func lowerLimit() throws {
        var settings = CurfewSettings.default
        settings.extensionWeeklyLimit = 2
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(dayToken: "2026-11-02", extensionUses: 5))
        let result = try BudgetCommand.snapshot(
            settings: settings,
            store: store,
            now: budgetDate(day: 2),
            calendar: budgetCalendar()
        )
        let extensions = try #require(result["extensions"] as? [String: Int])
        #expect(extensions["used"] == 5)
        #expect(extensions["remaining"] == 0)
    }

    @Test("Missing runtime authority cannot become a full budget")
    func missingRuntime() {
        #expect(throws: (any Error).self) {
            try BudgetCommand.snapshot(
                settings: .default,
                store: EnforcementRuntimeStateStore(),
                now: Date(),
                calendar: .current
            )
        }
    }

    @Test("Corrupt runtime authority cannot become a full budget")
    func corruptRuntime() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("bad runtime".utf8).write(to: url)
        #expect(throws: (any Error).self) {
            try BudgetCommand.snapshot(
                settings: .default,
                store: EnforcementRuntimeStateStore(recordURL: url),
                now: Date(),
                calendar: .current
            )
        }
        #expect(try Data(contentsOf: url) == Data("bad runtime".utf8))
    }

    @Test("Runtime reads reject symlinks rather than following another authority file")
    func runtimeRejectsSymlink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.json")
        try JSONEncoder().encode(EnforcementRuntimeState(dayToken: "2026-11-02")).write(to: target)
        let link = directory.appendingPathComponent("runtime.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: (any Error).self) {
            try EnforcementRuntimeStateStore(recordURL: link).load()
        }
    }
}

private func budgetCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    return calendar
}

private func budgetDate(month: Int = 11, day: Int, hour: Int = 0) throws -> Date {
    try #require(budgetCalendar().date(from: DateComponents(
        year: 2026,
        month: month,
        day: day,
        hour: hour
    )))
}
