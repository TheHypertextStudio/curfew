import CurfewKit

#if DEBUG
    import AppKit
    import Foundation

    /// Demo-fixture wiring for `CurfewAppModel`. Builds a model backed by
    /// throwaway stores seeded with curated state (see ``DemoFixture``) and
    /// drives it into a chosen surface for marketing / debug capture.
    ///
    /// Compiled only into Debug builds. The model is deliberately never armed
    /// (`start()` is not called) so the 1 Hz tick loop — and therefore the
    /// auto-shutdown workflow, which only advances inside a tick — never runs.
    /// Combined with `autoShutdownEnabled = false` in the seeded settings,
    /// this guarantees a capture run can never power off the machine.
    ///
    /// Demo launches are also hermetic with respect to shared storage: the
    /// activity log is a throwaway temp database, and `featureFlags.default`
    /// keeps `widgetKitEnabled` off so nothing writes the App Group container.
    @MainActor
    extension CurfewAppModel {
        /// Constructs a demo model backed by an ephemeral `UserDefaults` suite
        /// and a temporary on-disk activity log so the user's real settings and
        /// history are never touched. The scenario is applied separately via
        /// ``applyDemoScenario(_:)`` once the scene is on screen.
        static func demoModel() -> CurfewAppModel {
            CurfewAppModel(
                settingsStore: makeDemoSettingsStore(),
                appRouter: SystemAppRouter(),
                featureFlags: .shippingV1,
                activityRecorder: makeDemoActivityRecorder(now: Date())
            )
        }

        /// Applies the scenario after launch: pins the presented clock, swaps
        /// in the synthetic evaluation, and opens the right surface. Called
        /// from `CurfewApp` once the run loop has spun so windows and screens
        /// are ready.
        func applyDemoScenario(_ scenario: DemoScenario) {
            // Force the app to the foreground. Demo launches (especially the
            // first one under XCUITest) otherwise sometimes settle in
            // "Running Background", which both spoils captures and trips the
            // UI-test activation check.
            NSApp.activate(ignoringOtherApps: true)

            currentTime = DemoFixture.referenceTime(for: scenario, now: Date())
            state = DemoFixture.evaluation(for: scenario, now: currentTime)
            lockoutMessage = DemoFixture.lockoutMessage

            switch scenario {
            case .settings:
                privilegedHelperManager.seedDemoUnavailableError()
                openSettings()
            case .gettingStarted:
                settings.hasCompletedInitialSetup = false
                showGettingStarted()
            case .overview, .configuration, .thisWeek, .menuBar:
                break
            case .warning, .lockout, .reel:
                // Defer one more run-loop turn so the overlay windows land
                // above the just-created main window.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    overlayCoordinator.updateOverlays(
                        for: state,
                        model: self,
                        lockoutMessage: lockoutMessage
                    )
                }
            }
        }

        private static func makeDemoSettingsStore() -> CurfewSettingsStore {
            // Deliberately not a dotted sub-domain of the bundle identifier —
            // `UserDefaults(suiteName:)` rejects names that look like the app's
            // own domain ("nonsensical suite") and silently no-ops.
            let suiteName = "CurfewDemoFixture"
            // Start from a clean slate every launch so prior runs can't leak.
            UserDefaults().removePersistentDomain(forName: suiteName)
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let store = CurfewSettingsStore(defaults: defaults)
            store.save(DemoFixture.demoSettings())
            // Consume the first-run flag so onboarding doesn't auto-open; the
            // `gettingStarted` scenario opens it explicitly instead.
            _ = store.consumeShouldShowInitialSetup()
            return store
        }

        private static func makeDemoActivityRecorder(now: Date) -> any ActivityRecording {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("curfew-demo-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let store = try ActivityStore(directory: directory)
                for event in DemoFixture.seededActivityEvents(now: now) {
                    try? store.append(event)
                }
                return ActivityRecorder(store: store)
            } catch {
                return NullActivityRecording()
            }
        }
    }
#endif
