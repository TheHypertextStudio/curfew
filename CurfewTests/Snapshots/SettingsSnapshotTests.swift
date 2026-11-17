import CurfewKit
#if DEBUG
    import AppKit
    @testable import Curfew
    import SwiftUI
    import XCTest

    extension DestinationSnapshotTests {
        func testRenderLiteralCopySurfaces() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            try renderHosted(
                SettingsView().environment(model),
                named: "copy-settings", width: 900, height: 680, to: directory
            )
            try renderHosted(
                EveningReflectionCard(usesSolidPanels: true).environment(model)
                    .background(HorizonSkyView(
                        frame: model.horizonFrame, isDayRunning: false
                    ))
                    .environment(\.horizonSkyRendering, .reference),
                named: "copy-reflection", width: 650, height: 650, to: directory
            )
            try renderHosted(
                SunriseGateView().environment(model)
                    .transaction { $0.disablesAnimations = true },
                named: "copy-start-reflection", width: 900, height: 950,
                settlingTime: 1.1, to: directory
            )
        }

        func testRenderSettingsCategories() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            for section in SettingsSection.allCases {
                try renderHosted(
                    SettingsView(initialSection: section).environment(model),
                    named: "settings-\(section.id)", width: 900, height: 680, to: directory
                )
            }
            try renderHosted(
                SettingsView(initialSection: .protectedWork).environment(model),
                named: "settings-protected-work-compact", width: 760, height: 580, to: directory
            )
        }

        func testRenderSettingsDetailsAndDarkAppearance() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            model.settings.presence.cameraEnabled = true
            model.settings.presence.warnsWhenDistracted = true
            for section in [SettingsSection.enforcement, .protectedWork, .presence] {
                try renderHosted(
                    SettingsView(initialSection: section, expandedDetails: true)
                        .environment(model),
                    named: "settings-\(section.id)-expanded", width: 900, height: 680, to: directory
                )
                try renderHosted(
                    SettingsView(initialSection: section).environment(model),
                    named: "settings-\(section.id)-dark", width: 760, height: 580,
                    appearance: .darkAqua, to: directory
                )
            }
            model.settings.presence.warnsWhenDistracted = false
            try renderHosted(
                SettingsView(initialSection: .presence).environment(model),
                named: "settings-presence-reminders-off", width: 760, height: 580, to: directory
            )
            XCTAssertFalse(model.isPresenceCameraLive)
        }

        /// Warnings and limits with nothing waiting, then with two raises
        /// waiting, in both appearances.
        func testRenderWaitingLimitRaises() throws {
            let directory = try Self.snapshotsDirectory()
            let model = Self.demoModel()
            for (state, appearance) in [
                ("steady", NSAppearance.Name.aqua), ("steady", .darkAqua)
            ] {
                try renderHosted(
                    SettingsView(initialSection: .enforcement).environment(model),
                    named: "settings-limits-\(state)-\(appearance == .aqua ? "light" : "dark")",
                    width: 760, height: 580, appearance: appearance, to: directory
                )
            }
            XCTAssertTrue(model.settings.hasCompletedInitialSetup)
            let extensions = model.settings.extensionWeeklyLimit
            let overrideMinutes = model.settings.overrideDurationMinutes
            model.requestLimit(.extensionCount, value: extensions + 3)
            model.requestLimit(.overrideMinutes, value: overrideMinutes + 15)
            XCTAssertEqual(model.settings.extensionWeeklyLimit, extensions)
            XCTAssertEqual(model.settings.pendingLimitChanges.count, 2)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                try renderHosted(
                    SettingsView(initialSection: .enforcement).environment(model),
                    named: "settings-limits-waiting-\(appearance == .aqua ? "light" : "dark")",
                    width: 760, height: 580, appearance: appearance, to: directory
                )
            }
        }

        func testRenderShippingSettingsIntegrations() throws {
            let directory = try Self.snapshotsDirectory()
            let suite = "CurfewSettingsSnapshot-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = CurfewSettingsStore(defaults: defaults)
            store.save(DemoFixture.demoSettings())
            let model = CurfewAppModel(
                settingsStore: store,
                appRouter: AppRouterSpy(),
                isDemoSession: true,
                featureFlags: .shippingV1,
                activityRecorder: NullActivityRecording(),
                lockoutDeadlineStore: .ephemeralForTesting()
            )
            try renderHosted(
                SettingsView(initialSection: .integrations).environment(model),
                named: "settings-shipping-integrations", width: 900, height: 680, to: directory
            )
        }
    }
#endif
