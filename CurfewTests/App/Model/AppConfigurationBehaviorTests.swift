// Behavior tests for app-level configuration, launch, and coordinator wiring.
//
// Covers: Info.plist assumptions, launch-policy gating (enforcement is
// disarmed in Debug by default), feature-flag defaults, `AppCoordinator`
// start/stop contract, and the `EnforcementSnapshot` read model. Kept
// separate from feature-specific behavior tests so changes to the launch
// or wiring surface can be reviewed in isolation.

import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct AppConfigurationTests {
    @Test("Host app disables LSUIElement so it launches as a normal app window")
    func hostAppIsWindowed() throws {
        // Match the host app by its actual running bundle id — `…curfew` in
        // production, `…curfew.dev` in a development build — rather than a
        // hardcoded literal, so the flavor split doesn't break the assertion.
        let appBundle = try #require(Bundle.allBundles
            .first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }))
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

    @Test("Release launches always arm enforcement; CURFEW_SKIP_ENFORCEMENT is Debug-only")
    func releaseLaunchStartsByDefault() {
        #expect(CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: false))
        // Release ignores CURFEW_SKIP_ENFORCEMENT — a user-controllable env var
        // must not disable enforcement once the binary has been notarised and
        // distributed. The variable is honored only in Debug builds for local
        // development. CI smoke tests use Debug builds or a dedicated launch
        // argument outside the env-var surface.
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_SKIP_ENFORCEMENT": "1"],
                isDebugBuild: false
            )
        )
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_ENABLE_ENFORCEMENT": "0"],
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
        #expect(!flags.calendarEnabled)
    }

    @Test("Default build hides deferred integration panels")
    func deferredPanelsAreHiddenByDefault() {
        #expect(DeferredFeaturePanel.visible(for: .default).isEmpty)
    }

    @Test("Initial Release enables only the local MCP integration")
    func shippingEnablesOnlyValidatedLocalIntegration() {
        let flags = FeatureFlags.shipping
        #expect(flags.widgetKitEnabled == false)
        #expect(flags.cloudSyncEnabled == false)
        #expect(flags.mcpServerEnabled)
        #expect(flags.privilegedHelperEnabled == false)
        #expect(flags.calendarEnabled == false)
    }

    @Test("Resolution returns default when RELEASE_FEATURES is absent")
    func resolveWithoutReleaseFeatures() {
        #expect(
            FeatureFlags.resolve(releaseFeaturesEnabled: false, environment: [:])
                == .default
        )
    }

    @Test("Resolution returns shipping when RELEASE_FEATURES is present")
    func resolveWithReleaseFeatures() {
        #expect(
            FeatureFlags.resolve(releaseFeaturesEnabled: true, environment: [:])
                == .shipping
        )
    }

    @Test("Conservative-flags escape hatch forces default even under RELEASE_FEATURES")
    func conservativeEscapeHatchForcesDefault() {
        #expect(
            FeatureFlags.resolve(
                releaseFeaturesEnabled: true,
                environment: ["CURFEW_CONSERVATIVE_FLAGS": "1"]
            ) == .default
        )
        // A non-"1" value does not trip the escape hatch.
        #expect(
            FeatureFlags.resolve(
                releaseFeaturesEnabled: true,
                environment: ["CURFEW_CONSERVATIVE_FLAGS": "0"]
            ) == .shipping
        )
    }

    @Test("Resolved is .default in the Debug/test build (no RELEASE_FEATURES)")
    func resolvedMatchesDebugBuild() {
        // The test host is a Debug build and never defines RELEASE_FEATURES,
        // so the live `resolved` accessor must collapse to the all-off default.
        #expect(FeatureFlags.resolved == .default)
    }
}

struct WidgetIdentityTests {
    @Test("Widget timeline reloads use the flavor's extension kind identifier")
    func kindMatchesWidgetExtension() {
        // Flavor-suffixed so a dev build's timelines stay distinct from
        // production; the app and the widget extension derive the same value.
        // The Debug/dev test host resolves the `.dev` variant.
        #expect(CurfewWidgetIdentity.kind.hasSuffix(".widget"))
        #expect(
            CurfewWidgetIdentity.kind
                == "studio.hypertext.curfew\(CurfewFlavor.current.identifierSuffix).widget"
        )
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

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy()
        )

        let coordinator = AppCoordinator()
        coordinator.handleInitialLaunch(
            model: model,
            shouldStartEnforcement: true
        )

        #expect(model.isEnforcementRunning)
        #expect(model.gettingStartedRequestID == 1)
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
            appRouter: AppRouterSpy()
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
    @Test("Main workspace navigation is Today, Schedule, and Journal")
    func sectionSet() {
        #expect(MainWorkspaceSection.allCases == [.today, .schedule, .journal])
    }
}

struct SettingsSectionTests {
    @Test("Settings sections are enforcement, integrations, advanced, and about")
    func sectionSet() {
        #expect(
            SettingsSection.allCases == [
                .enforcement,
                .integrations,
                .advanced,
                .about
            ]
        )
    }
}

struct CurfewUpdaterTests {
    @Test("Current build only shows update UI when Sparkle is linked")
    func updateAvailabilityMatchesLinkedFramework() {
        #expect(CurfewUpdater.isAvailable == false)
    }
}

struct ShutdownSupportTests {
    @Test("Current build only shows auto-shutdown when Apple Events entitlement is present")
    func shutdownAvailabilityMatchesEntitlements() throws {
        // Match the host app by its actual running bundle id — `…curfew` in
        // production, `…curfew.dev` in a development build — rather than a
        // hardcoded literal, so the flavor split doesn't break the assertion.
        let appBundle = try #require(Bundle.allBundles
            .first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }))

        #expect(ShutdownSupport.isAvailable(in: appBundle) == false)
    }
}
