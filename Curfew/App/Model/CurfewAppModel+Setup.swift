import CurfewKit
import Foundation
import OSLog

/// Convenience initialisers used by tests and the production entry point.
/// Split into its own extension so the designated init in the main file
/// doesn't grow unbounded as new optional collaborators are added.
extension CurfewAppModel {
    /// Convenience for tests that only need to override the routing /
    /// onboarding presenter; defaults everything else (including the
    /// activity recorder, which falls back to the null recording when the
    /// SQLite store cannot be opened).
    ///
    /// `respawnGuard` is plumbed through with a `NoOpRespawnGuard()`
    /// default so production callers (`CurfewApp` zero-arg init) can
    /// override it with the real ``PersistentLockdown`` while tests keep
    /// the no-op behavior without changing their construction calls.
    convenience init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        featureFlags: FeatureFlags = .default,
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard(),
        accessibilityAuthorization: AccessibilityAuthorizing = SystemAccessibilityAuthorization()
    ) {
        self.init(
            settingsStore: settingsStore,
            appRouter: appRouter,
            featureFlags: featureFlags,
            activityRecorder: Self.defaultActivityRecording(),
            reflectionState: ReflectionRuntimeState(
                recorder: Self.defaultReflectionRecording()
            ),
            respawnGuard: respawnGuard,
            accessibilityAuthorization: accessibilityAuthorization
        )
    }

    /// Convenience for call sites that only want to override routing; uses a
    /// default ``CurfewSettingsStore``.
    convenience init(
        appRouter: AppRouting
    ) {
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: appRouter
        )
    }

    /// Builds the extension and override budget trackers from `settings` in one
    /// call, keeping the designated init body inside the lint-enforced budget.
    static func makeBudgetTrackers(
        for settings: CurfewSettings
    ) -> (extension: ExtensionBudgetTracker, override: ExtensionBudgetTracker) {
        let extensionTracker = ExtensionBudgetTracker(
            weeklyLimit: settings.extensionWeeklyLimit,
            extensionMinutes: settings.extensionDurationMinutes,
            resetWeekday: settings.resetWeekday
        )
        let overrideTracker = ExtensionBudgetTracker(
            weeklyLimit: settings.overrideWeeklyLimit,
            extensionMinutes: settings.overrideDurationMinutes,
            resetWeekday: settings.resetWeekday
        )
        return (extension: extensionTracker, override: overrideTracker)
    }

    /// UserDefaults key recording that the one-time activity-database
    /// migration out of the App Group container has been attempted. Stored in
    /// the standard suite (not signature-tied) so even repeated ad-hoc Debug
    /// rebuilds never re-touch the shared container.
    static let activityMigrationDefaultsKey = "curfew.activityDB.migratedToAppSupport.v1"

    /// Opens the canonical ``ActivityStore`` in the app's own Application
    /// Support directory, wrapping it in an ``ActivityRecorder``. On any
    /// failure (disk full, permissions), falls back to a
    /// ``NullActivityRecording`` so the app keeps enforcing without telemetry.
    static func defaultActivityRecording() -> any ActivityRecording {
        let canonical = SharedPaths.activityDatabase
        do {
            try FileManager.default.createDirectory(
                at: canonical.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            migrateActivityDatabaseFromSharedContainerOnce(canonical: canonical)
            let store = try ActivityStore(databaseURL: canonical)
            return ActivityRecorder(store: store)
        } catch {
            let logger = Logger(subsystem: "studio.hypertext.curfew", category: "app-model")
            logger.error("activity recorder unavailable: \(String(describing: error))")
            return NullActivityRecording()
        }
    }

    /// Opens the canonical ``ReflectionStore`` in the app's own Application
    /// Support directory, wrapping it in a ``ReflectionRecorder``. On any
    /// failure (disk full, permissions), falls back to a
    /// ``NullReflectionRecording`` so reflection prompting still works in
    /// memory even though nothing persists. Mirrors ``defaultActivityRecording``.
    static func defaultReflectionRecording() -> any ReflectionRecording {
        let canonical = SharedPaths.reflectionDatabase
        do {
            try FileManager.default.createDirectory(
                at: canonical.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let store = try ReflectionStore(databaseURL: canonical)
            return ReflectionRecorder(store: store)
        } catch {
            let logger = Logger(subsystem: "studio.hypertext.curfew", category: "app-model")
            logger.error("reflection recorder unavailable: \(String(describing: error))")
            return NullReflectionRecording()
        }
    }

    /// One-time migration of the activity log from its former App Group
    /// container location into ``SharedPaths/activityDatabase``.
    ///
    /// Guarded by a UserDefaults flag so the App Group container is touched at
    /// most once, ever — after that the app never reaches into
    /// `~/Library/Group Containers`, which is what stops the recurring macOS
    /// "access data from other apps" prompt. `source` is an `@autoclosure` so
    /// the shared-container path is only resolved (which itself can prompt)
    /// when a migration is actually due. The shared-container copy is the
    /// superset of history (the previous layout copied Application Support →
    /// shared, then appended), so it overwrites any stale canonical copy.
    static func migrateActivityDatabaseFromSharedContainerOnce(
        canonical: URL,
        source: @autoclosure () -> URL = SharedPaths.sharedContainerActivityDatabase,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        guard !defaults.bool(forKey: activityMigrationDefaultsKey) else { return }
        defaults.set(true, forKey: activityMigrationDefaultsKey)

        let sourceURL = source()
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        try? fileManager.removeItem(at: canonical)
        try? fileManager.copyItem(at: sourceURL, to: canonical)
    }
}
