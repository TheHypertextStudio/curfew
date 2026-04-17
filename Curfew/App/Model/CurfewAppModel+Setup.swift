import Foundation
import OSLog

extension CurfewAppModel {
    /// Convenience for tests that only need to override the routing /
    /// onboarding presenter; defaults everything else (including the
    /// activity recorder, which falls back to the null recording when the
    /// SQLite store cannot be opened).
    convenience init(
        settingsStore: CurfewSettingsStore,
        appRouter: AppRouting,
        gettingStartedPresenter: GettingStartedPresenting,
        featureFlags: FeatureFlags = .default
    ) {
        self.init(
            settingsStore: settingsStore,
            appRouter: appRouter,
            gettingStartedPresenter: gettingStartedPresenter,
            featureFlags: featureFlags,
            activityRecorder: Self.defaultActivityRecording()
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
        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = appSupport.appendingPathComponent("Curfew", isDirectory: true)
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let store = try ActivityStore(directory: directory)
            return ActivityRecorder(store: store)
        } catch {
            let logger = Logger(subsystem: "studio.hypertext.curfew", category: "app-model")
            logger.error("activity recorder unavailable: \(String(describing: error))")
            return NullActivityRecording()
        }
    }
}
