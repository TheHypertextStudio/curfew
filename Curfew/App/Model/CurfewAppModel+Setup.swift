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
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = .default,
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard()
    ) {
        self.init(
            settingsStore: settingsStore,
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter,
            featureFlags: featureFlags,
            activityRecorder: Self.defaultActivityRecording(),
            respawnGuard: respawnGuard
        )
    }

    /// Convenience for call sites that only want to override routing +
    /// onboarding presenter; uses a default ``CurfewSettingsStore``.
    convenience init(
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting
    ) {
        self.init(
            settingsStore: CurfewSettingsStore(),
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter
        )
    }

    /// Resolves the `Application Support/Curfew` directory and opens an
    /// ``ActivityStore`` at `activity.sqlite3` inside it, wrapping it in
    /// an ``ActivityRecorder``. On any failure (sandbox, disk full), falls
    /// back to a ``NullActivityRecording`` so the app can continue to
    /// enforce normally without telemetry. Failures are logged via
    /// `os.Logger` so Console.app and sysdiagnose capture them.
    static func defaultActivityRecording() -> any ActivityRecording {
        do {
            let sharedStateStore = WidgetSharedStateStore()
            try sharedStateStore.prepareActivityDatabase()
            let store = try ActivityStore(databaseURL: SharedPaths.activityDatabase)
            return ActivityRecorder(store: store)
        } catch {
            let logger = Logger(subsystem: "studio.hypertext.curfew", category: "app-model")
            logger.error("activity recorder unavailable: \(String(describing: error))")
            return NullActivityRecording()
        }
    }
}
