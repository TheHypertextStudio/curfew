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
            for enforcing in [false, true] {
                let copy = TodayView.control(needsSetup: false, enforcing: enforcing)
                try render(
                    TodaySundownView(
                        statusLine: copy.line, statusDetail: copy.detail,
                        isEnforcing: enforcing, primaryActionLabel: copy.action
                    ),
                    named: enforcing ? "copy-today-on" : "copy-today-off",
                    width: 900, height: 680, to: directory
                )
            }
            let copy = TodayView.control(needsSetup: false, enforcing: true)
            try render(
                TodaySundownView(
                    statusLine: copy.line, statusDetail: copy.detail,
                    isEnforcing: true, showAccessibilityWarning: true
                ),
                named: "copy-today-permission", width: 600, height: 740, to: directory
            )
            try renderHosted(
                SettingsView().environment(model),
                named: "copy-settings", width: 900, height: 680, to: directory
            )
            try renderHosted(
                EveningReflectionCard(usesSolidPanels: true).environment(model)
                    .background(SundownSky(moment: model.skyMoment)),
                named: "copy-reflection", width: 650, height: 650, to: directory
            )
            try renderHosted(
                DaybreakReflectionView().environment(model)
                    .transaction { $0.disablesAnimations = true },
                named: "copy-start-reflection", width: 900, height: 950,
                settlingTime: 1.1, to: directory
            )
            try render(
                LockoutSundownView(message: "Rest well."),
                named: "copy-lockout", width: 1200, height: 800, to: directory
            )
            try render(
                LockoutSundownView(message: EncouragementMessageCatalog.next(after: nil)),
                named: "copy-remote-lockout", width: 1200, height: 800, to: directory
            )
            try render(
                JournalSundownView(), named: "copy-journal", width: 900, to: directory
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
