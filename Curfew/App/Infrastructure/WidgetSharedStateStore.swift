import Foundation
import OSLog

private let widgetSharedStateLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "widget-shared-state"
)

/// Bridges app-owned state into widget-readable storage.
///
/// The main app still owns its private `UserDefaults` domain. This store
/// mirrors the subset the widget needs into a shared JSON snapshot and also
/// migrates the activity SQLite database into the shared container so the
/// future widget target can read it without reaching into the app's legacy
/// `~/Library/Application Support/Curfew` directory.
struct WidgetSharedStateStore {
    let fileManager: FileManager
    let settingsURL: URL
    let activityDatabaseURL: URL
    let legacyActivityDatabaseURL: URL

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        settingsURL: URL = SharedPaths.widgetSettingsSnapshot,
        activityDatabaseURL: URL = SharedPaths.activityDatabase,
        legacyActivityDatabaseURL: URL = SharedPaths.legacyActivityDatabase
    ) {
        self.fileManager = fileManager
        self.settingsURL = settingsURL
        self.activityDatabaseURL = activityDatabaseURL
        self.legacyActivityDatabaseURL = legacyActivityDatabaseURL
    }

    /// Persists a JSON snapshot the widget can decode independently of the
    /// app's private `UserDefaults` suite.
    func sync(settings: CurfewSettings) throws {
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
        widgetSharedStateLogger.info("widget settings snapshot synced")
    }

    /// Reads the mirrored settings snapshot, or defaults when no snapshot has
    /// been written yet (first launch / pre-migration installs).
    func loadSettings() -> CurfewSettings {
        guard let data = try? Data(contentsOf: settingsURL) else {
            return .default
        }
        return (try? decoder.decode(CurfewSettings.self, from: data)) ?? .default
    }

    /// Ensures the shared activity database directory exists and performs a
    /// one-time copy from the legacy location when the shared DB is still
    /// absent. Safe to call on every launch.
    func prepareActivityDatabase() throws {
        try fileManager.createDirectory(
            at: activityDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(atPath: activityDatabaseURL.path) else {
            return
        }
        guard fileManager.fileExists(atPath: legacyActivityDatabaseURL.path) else {
            return
        }

        try fileManager.copyItem(at: legacyActivityDatabaseURL, to: activityDatabaseURL)
        widgetSharedStateLogger.info("migrated legacy activity database into widget shared storage")
    }
}
