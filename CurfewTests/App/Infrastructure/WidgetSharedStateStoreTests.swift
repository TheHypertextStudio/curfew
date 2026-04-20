@testable import Curfew
import Foundation
import Testing

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
            activityDatabaseURL: tempRoot.appendingPathComponent("activity.sqlite3"),
            legacyActivityDatabaseURL: tempRoot.appendingPathComponent("legacy.sqlite3")
        )
        var settings = CurfewSettings.default
        settings.extensionWeeklyLimit = 7
        settings.overrideWeeklyLimit = 4
        settings.autoShutdownDelayMinutes = 12

        try store.sync(settings: settings)

        #expect(store.loadSettings() == settings)
    }

    @Test("Shared activity database copies the legacy database on first migration")
    func migratesLegacyActivityDatabase() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let sharedURL = tempRoot.appendingPathComponent("shared/activity.sqlite3")
        let legacyURL = tempRoot.appendingPathComponent("legacy/activity.sqlite3")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyData = Data("legacy-db".utf8)
        try legacyData.write(to: legacyURL, options: .atomic)

        let store = WidgetSharedStateStore(
            settingsURL: tempRoot.appendingPathComponent("widget-settings.json"),
            activityDatabaseURL: sharedURL,
            legacyActivityDatabaseURL: legacyURL
        )

        try store.prepareActivityDatabase()

        #expect(FileManager.default.fileExists(atPath: sharedURL.path))
        #expect(try Data(contentsOf: sharedURL) == legacyData)
    }
}
