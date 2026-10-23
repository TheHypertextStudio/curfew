import CurfewKit

#if DEBUG
    import AppKit
    import Foundation

    /// Demo-fixture wiring for `CurfewAppModel`. Builds a model backed by
    /// throwaway stores seeded with curated state (see ``DemoFixture``) and
    /// drives it into a chosen surface for marketing / debug capture.
    ///
    /// Release cannot select a fixture. Ordinary captures stay disarmed;
    /// the background-enforcement fixture runs the real timer with a controlled
    /// clock, temporary stores, and shutdown disabled. Keyboard interception
    /// requires an explicit opt-in in a signed staging bundle.
    @MainActor
    extension CurfewAppModel {
        /// Constructs a demo model backed by an ephemeral `UserDefaults` suite
        /// and a temporary on-disk activity log so the user's real settings and
        /// history are never touched. The scenario is applied separately via
        /// ``applyDemoScenario(_:)`` once the scene is on screen.
        static func demoModel(backgroundEnforcement: Bool = false) -> CurfewAppModel {
            let now = Date()
            let settingsStore = makeDemoSettingsStore()
            configureBackgroundDemo(settingsStore, enabled: backgroundEnforcement)
            let workingTime = DemoFixture.referenceTime(for: .overview, now: now)
            let lockedTime = DemoFixture.referenceTime(for: .lockout, now: now)
            let deadline = Bundle.main
                .object(forInfoDictionaryKey: "CurfewAcceptanceDeadline") as? Date
                ?? now.addingTimeInterval(5)
            return CurfewAppModel(
                settingsStore: settingsStore,
                appRouter: SystemAppRouter(),
                isDemoSession: true,
                featureFlags: backgroundEnforcement ? .default
                    : DemoReviewState.current == .accountHelperHidden ? .default
                    : DemoReviewState.current.enablesPreviewConnections
                    ? FeatureFlags(
                        widgetKitEnabled: true,
                        cloudSyncEnabled: true,
                        mcpServerEnabled: true,
                        privilegedHelperEnabled: true,
                        calendarEnabled: true
                    )
                    : .shippingV1,
                activityRecorder: makeDemoActivityRecorder(now: now),
                notificationManager: NoOpWarningNotificationManager(),
                licenseGate: LicenseGate(defaults: UserDefaults(suiteName: "CurfewDemoLicense")),
                accountSyncEngine: AccountSyncEngine(transport: NoOpAccountSyncTransport()),
                privilegedHelperManager: PrivilegedHelperManager(
                    daemonService: DemoAppService(), loginItemService: DemoAppService(),
                    daemonRPC: DemoDaemonRPC()
                ),
                lockoutDeadlineStore: LockoutDeadlineStore(recordURL: FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("CurfewDemo-\(UUID().uuidString).json")),
                accessibilityAuthorization: backgroundEnforcement &&
                    RuntimeEnvironment.shouldInstallKeyboardInterceptor
                    ? SystemAccessibilityAuthorization() : DemoAccessibilityAuthorization(),
                browserNativeRuntime: makeDemoBrowserRuntime(
                    defaults: settingsStore.storageDefaults,
                    now: now
                ),
                runtimeNow: backgroundEnforcement ? workingTime : now,
                enforcementClock: backgroundEnforcement
                    ? { Date() >= deadline ? lockedTime : workingTime } : Date.init,
                backgroundAcceptance: backgroundEnforcement
            )
        }

        /// Applies the scenario after launch: pins the presented clock, swaps
        /// in the synthetic evaluation, and opens the right surface. Called
        /// from `CurfewApp` once the run loop has spun so windows and screens
        /// are ready.
        func applyDemoScenario(_ scenario: DemoScenario) {
            if scenario == .backgroundEnforcement {
                start()
                recordBackgroundAcceptanceState()
                return
            }
            // Force the app to the foreground. Demo launches (especially the
            // first one under XCUITest) otherwise sometimes settle in
            // "Running Background", which both spoils captures and trips the
            // UI-test activation check.
            NSApp.activate(ignoringOtherApps: true)

            currentTime = DemoFixture.referenceTime(for: scenario, now: Date())
            state = DemoFixture.evaluation(for: scenario, now: currentTime)
            lockoutMessage = DemoFixture.lockoutMessage
            applyDemoReviewState(DemoReviewState.current)

            switch scenario {
            case .settings:
                if DemoReviewState
                    .current == .normal {
                    privilegedHelperManager.seedDemoUnavailableError()
                }
                openSettings()
            case .gettingStarted:
                if ![DemoReviewState.setupReview, .setupReviewDenied].contains(.current) {
                    settings.hasCompletedInitialSetup = false
                }
                showGettingStarted()
            case .overview, .configuration, .thisWeek, .menuBar, .backgroundEnforcement:
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

        private static func configureBackgroundDemo(
            _ store: CurfewSettingsStore, enabled: Bool
        ) {
            guard enabled else { return }
            var settings = store.load()
            for day in Weekday.allCases {
                settings.schedule.rules[day] = DayRule(
                    isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 7 * 60
                )
            }
            store.save(settings)
            store.saveAutomaticScheduleConsent(true)
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
            var settings = DemoFixture.demoSettings()
            if ProcessInfo.processInfo.environment["CURFEW_DEMO_SCENARIO"] == "getting-started" {
                settings.hasCompletedInitialSetup = false
            }
            store.save(settings)
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

        private static func makeDemoBrowserRuntime(
            defaults: UserDefaults,
            now: Date
        ) -> BrowserNativeRuntime {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "curfew-demo-browser-\(UUID().uuidString)",
                isDirectory: true
            )
            let nativeStore = BrowserNativeStore(directory: directory)
            do {
                try nativeStore.activate()
                try nativeStore.recordHeartbeat(
                    origin: "chrome-extension://curfew-demo",
                    at: now
                )
            } catch {
                preconditionFailure("The browser demo store could not be created: \(error)")
            }

            let credentials = DocketCredentialStore(secretStore: DemoBrowserSecretStore())
            do {
                try credentials.save(DocketOAuthTokens(
                    accessToken: "demo-access-token",
                    refreshToken: "demo-refresh-token",
                    expiresAt: now.addingTimeInterval(3600)
                ))
            } catch {
                preconditionFailure("The browser demo credentials could not be created: \(error)")
            }
            let coordinator = DocketBrowserPolicyCoordinator(
                credentials: credentials,
                oauth: DemoDocketOAuth()
            )
            let runtime = BrowserNativeRuntime(
                store: nativeStore,
                coordinator: coordinator,
                startupIsAllowed: { false }
            )
            coordinator.seedDemo(DemoFixture.browserActiveWork(at: now), at: now)
            BrowserIntegrationSettingsStore(defaults: defaults)
                .save(DemoFixture.browserIntegrationSettings())
            return runtime
        }
    }

    private final class DemoBrowserSecretStore: AccountSecretStoring {
        private var values: [String: Data] = [:]

        func data(for account: String) throws -> Data? {
            values[account]
        }

        func save(_ data: Data, for account: String) throws {
            values[account] = data
        }

        func delete(_ account: String) throws {
            values.removeValue(forKey: account)
        }
    }

    @MainActor
    private final class DemoDocketOAuth: DocketOAuthAuthorizing {
        func connect(at _: Date) async throws -> DocketOAuthTokens {
            throw DocketClientError.unavailable
        }

        func refresh(now _: Date) async throws -> DocketOAuthTokens {
            throw DocketClientError.unavailable
        }
    }
#endif
