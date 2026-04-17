// Behavior tests for app-level configuration, launch, and coordinator wiring.
//
// Covers: Info.plist assumptions, launch-policy gating (enforcement is
// disarmed in Debug by default), feature-flag defaults, `AppCoordinator`
// start/stop contract, and the `EnforcementSnapshot` read model. Kept
// separate from feature-specific behavior tests so changes to the launch
// or wiring surface can be reviewed in isolation.

import AppKit
@testable import Curfew
import Foundation
import Testing

struct AppConfigurationTests {
    @Test("Host app disables LSUIElement so it launches as a normal app window")
    func hostAppIsWindowed() throws {
        let appBundle = try #require(Bundle.allBundles
            .first(where: { $0.bundleIdentifier == "studio.hypertext.curfew" }))
        let value = appBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool
        #expect(value == false)
    }
}

struct LaunchBehaviorTests {
    @Test("Debug launches keep enforcement disarmed unless explicitly enabled")
    func debugLaunchDefaultsToSafeMode() {
        #expect(!CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: true))
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_ENABLE_ENFORCEMENT": "1"],
                isDebugBuild: true
            )
        )
        #expect(
            !CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_SKIP_ENFORCEMENT": "1"],
                isDebugBuild: true
            )
        )
    }

    @Test("Release launches arm enforcement unless explicitly skipped")
    func releaseLaunchStartsByDefault() {
        #expect(CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: false))
        #expect(
            !CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_SKIP_ENFORCEMENT": "1"],
                isDebugBuild: false
            )
        )
    }
}

struct FeatureFlagTests {
    @Test("Deferred modules remain disabled by default")
    func defaultsAreOff() {
        let flags = FeatureFlags.default
        #expect(!flags.widgetKitEnabled)
        #expect(!flags.cloudSyncEnabled)
        #expect(!flags.mcpServerEnabled)
        #expect(!flags.privilegedHelperEnabled)
    }
}

@MainActor
struct AppCoordinatorTests {
    @Test("Coordinator starts enforcement when launch policy allows and setup is complete")
    func startsEnforcement() {
        let suiteName = "CurfewSettingsStoreTests.AppCoordinator.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)

        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        let coordinator = AppCoordinator()
        coordinator.handleInitialLaunch(
            model: model,
            shouldStartEnforcement: true
        )

        #expect(model.isEnforcementRunning)
        #expect(presenter.presentCallCount == 1)
    }

    @Test("Coordinator keeps enforcement disarmed when launch policy disables start")
    func doesNotStartWhenDisallowed() {
        let suiteName = "CurfewSettingsStoreTests.AppCoordinator.NoStart.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy()
        )

        let coordinator = AppCoordinator()
        coordinator.handleInitialLaunch(
            model: model,
            shouldStartEnforcement: false
        )

        #expect(!model.isEnforcementRunning)
    }
}

@MainActor
struct EnforcementSnapshotTests {
    @Test("Snapshot reflects warning-phase state and extension copy")
    func warningSnapshot() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: Date(timeIntervalSince1970: 1_700_000_000),
            unlockDate: Date(timeIntervalSince1970: 1_700_003_600)
        )
        model.extensionsRemaining = 2
        model.settings.extensionDurationMinutes = 20

        let snapshot = model.snapshot

        #expect(snapshot.phase == .warning)
        #expect(snapshot.symbolName == "exclamationmark.triangle")
        #expect(snapshot.statusLine == "Wrap up time")
        #expect(snapshot.timeRemainingText == "0:15")
        #expect(snapshot.canRequestExtension)
        #expect(snapshot.extensionsRemaining == 2)
        #expect(snapshot.extensionRequestTitle == "Hold 2s for +20m extension")
        #expect(snapshot.scheduleWindowText.contains("->"))
    }

    @Test("Snapshot shows idle messaging when no schedule window is active")
    func dayOffSnapshot() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        let snapshot = model.snapshot

        #expect(snapshot.phase == .dayOff)
        #expect(snapshot.symbolName == "moon.zzz")
        #expect(snapshot.timeRemainingText == "—")
        #expect(snapshot.scheduleWindowText == "No enforcement window is active today.")
        #expect(!snapshot.canRequestExtension)
    }
}

struct MainWorkspaceSectionTests {
    @Test("Main workspace navigation includes overview, configuration, and onboarding")
    func sectionSet() {
        #expect(MainWorkspaceSection.allCases == [.overview, .configuration, .onboarding])
    }
}

struct SettingsSectionTests {
    @Test("Settings sections include schedule, enforcement, integrations, devices, and advanced")
    func sectionSet() {
        #expect(
            SettingsSection.allCases == [
                .schedule,
                .enforcement,
                .integrations,
                .devices,
                .advanced
            ]
        )
    }
}
