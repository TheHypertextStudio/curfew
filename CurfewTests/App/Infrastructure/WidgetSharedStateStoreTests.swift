@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct WidgetSharedStateStoreTests {
    @Test("Widget settings snapshot round-trips current settings")
    func settingsSnapshotRoundTrips() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = WidgetSharedStateStore(
            settingsURL: tempRoot.appendingPathComponent("widget-settings.json"),
            enforcementURL: tempRoot.appendingPathComponent("widget-enforcement.json")
        )
        var settings = CurfewSettings.default
        settings.extensionWeeklyLimit = 7
        settings.overrideWeeklyLimit = 4
        settings.autoShutdownDelayMinutes = 12

        try store.sync(settings: settings)

        #expect(store.loadSettings() == settings)
    }

    @Test("Widget enforcement snapshot round-trips")
    func enforcementSnapshotRoundTrips() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = WidgetSharedStateStore(
            settingsURL: tempRoot.appendingPathComponent("widget-settings.json"),
            enforcementURL: tempRoot.appendingPathComponent("widget-enforcement.json")
        )
        let snapshot = WidgetEnforcementSnapshot(
            phase: "locked",
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: Date(timeIntervalSince1970: 1_700_000_000),
            unlockDate: Date(timeIntervalSince1970: 1_700_030_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )

        try store.sync(enforcement: snapshot)

        #expect(store.loadEnforcement() == snapshot)
    }

    @Test("Activity database migrates once from the shared container, then never again")
    func activityMigrationIsOneTime() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let canonical = tempRoot.appendingPathComponent("app-support/activity.sqlite3")
        let source = tempRoot.appendingPathComponent("group/activity.sqlite3")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: canonical.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try Data("group-db".utf8).write(to: source, options: .atomic)

        let suiteName = "test-migration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // First call migrates the shared-container database into place.
        CurfewAppModel.migrateActivityDatabaseFromSharedContainerOnce(
            canonical: canonical,
            source: source,
            defaults: defaults
        )
        #expect(FileManager.default.fileExists(atPath: canonical.path))
        #expect(try Data(contentsOf: canonical) == Data("group-db".utf8))

        // A subsequent call must be a no-op (flag set) — it must not clobber
        // newer canonical data with the stale shared-container copy.
        try Data("fresh-canonical".utf8).write(to: canonical, options: .atomic)
        CurfewAppModel.migrateActivityDatabaseFromSharedContainerOnce(
            canonical: canonical,
            source: source,
            defaults: defaults
        )
        #expect(try Data(contentsOf: canonical) == Data("fresh-canonical".utf8))
    }
}
