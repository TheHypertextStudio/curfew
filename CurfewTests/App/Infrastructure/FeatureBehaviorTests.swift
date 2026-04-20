// Behavior tests for warning notifications, overlay window configuration,
// encouragement message rotation, auto-shutdown, and warning-interval
// persistence.
//
// These tests anchor the runtime behavior of the user-visible "curfew is
// approaching" signals. Related tests were split into
// `OverrideAndExtensionBehaviorTests`, `AppConfigurationBehaviorTests`, and
// `OnboardingAndUIBehaviorTests` so each file stays under the SwiftLint
// file-length threshold.

import AppKit
@testable import Curfew
import Foundation
import Testing

@MainActor
struct WarningNotificationManagerTests {
    @Test("T-30 and T-15 notifications include snooze category without sound")
    func earlyWarningPayload() throws {
        let thirty = try #require(WarningNotificationManager.payload(for: .thirtyMinutes))
        let fifteen = try #require(WarningNotificationManager.payload(for: .fifteenMinutes))

        #expect(thirty.categoryIdentifier == WarningNotificationManager
            .warningSnoozeCategoryIdentifier)
        #expect(fifteen.categoryIdentifier == WarningNotificationManager
            .warningSnoozeCategoryIdentifier)
        #expect(!thirty.playsSound)
        #expect(!fifteen.playsSound)
    }

    @Test("Final warning notifications use standard category with sound")
    func finalWarningPayload() throws {
        let five = try #require(WarningNotificationManager.payload(for: .fiveMinutes))
        let two = try #require(WarningNotificationManager.payload(for: .twoMinutes))
        let one = try #require(WarningNotificationManager.payload(for: .oneMinute))

        #expect(five.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(two.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(one.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(five.playsSound)
        #expect(two.playsSound)
        #expect(one.playsSound)
    }

    @Test("Notification category definitions expose snooze action only in snooze category")
    func categoryDefinitions() {
        let definitions = WarningNotificationManager.categoryDefinitions()
        let byIdentifier = Dictionary(uniqueKeysWithValues: definitions.map { ($0.identifier, $0) })

        let snoozeDefinition =
            byIdentifier[WarningNotificationManager.warningSnoozeCategoryIdentifier]
        let warningDefinition = byIdentifier[WarningNotificationManager.warningCategoryIdentifier]

        #expect(snoozeDefinition?
            .actionIdentifiers == [WarningNotificationManager.snoozeActionIdentifier])
        #expect(warningDefinition?.actionIdentifiers == [])
    }
}

@MainActor
struct OverlayWindowConfigurationTests {
    @Test("Warning overlay windows are floating and click-through")
    func warningWindowConfiguration() {
        let configuration = OverlayCoordinator.warningWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.floating)
        #expect(configuration.ignoresMouseEvents)
        #expect(configuration.collectionBehavior
            .contains(NSWindow.CollectionBehavior.canJoinAllSpaces))
        #expect(configuration.collectionBehavior
            .contains(NSWindow.CollectionBehavior.fullScreenAuxiliary))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.stationary))
    }

    @Test("Lockout windows are screenSaver-level and capture input")
    func lockoutWindowConfiguration() {
        let configuration = OverlayCoordinator.lockoutWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.screenSaver)
        #expect(!configuration.ignoresMouseEvents)
        #expect(configuration.collectionBehavior
            .contains(NSWindow.CollectionBehavior.canJoinAllSpaces))
        #expect(configuration.collectionBehavior
            .contains(NSWindow.CollectionBehavior.fullScreenAuxiliary))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.stationary))
        #expect(!configuration.isMovable)
    }

    @Test("Floating timer windows stay above standard app content")
    func timerWindowConfiguration() {
        let configuration = OverlayCoordinator.timerWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.statusBar)
        #expect(configuration.ignoresMouseEvents)
    }
}

struct EncouragementMessageRotationTests {
    @Test("Encouragement messages rotate through all entries and wrap")
    func messageRotationWraps() {
        let first = EncouragementMessageCatalog.next(after: nil)
        let second = EncouragementMessageCatalog.next(after: first)
        let third = EncouragementMessageCatalog.next(after: second)
        let fourth = EncouragementMessageCatalog.next(after: third)
        let fifth = EncouragementMessageCatalog.next(after: fourth)
        let wrapped = EncouragementMessageCatalog.next(after: fifth)

        #expect(first != second)
        #expect(second != third)
        #expect(third != fourth)
        #expect(fourth != fifth)
        #expect(wrapped == first)
    }
}

struct AutoShutdownConfigurationTests {
    @Test("Default auto-shutdown delay is 10 minutes")
    func defaultAutoShutdownDelay() {
        #expect(CurfewSettings.default.autoShutdownDelayMinutes == 10)
    }

    @Test("Shutdown countdown status line appears while waiting")
    func shutdownCountdownStatusLine() {
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        let status = workflow.statusLine(now: now)
        #expect(status?.contains("10:00") == true)
    }

    @Test("Shutdown delay clamps to one minute minimum")
    func shutdownDelayMinimumClamp() {
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 0,
            controller: spy
        )

        let status = workflow.statusLine(now: now)
        #expect(status?.contains("1:00") == true)
    }

    @Test("Permission-denied shutdown status points users to Automation settings")
    func shutdownPermissionDeniedStatusLine() {
        var workflow = ShutdownWorkflow()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let spy = ShutdownControllerSpy(outcomes: [.permissionDenied])

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 1,
            controller: spy
        )
        workflow.update(
            now: now.addingTimeInterval(61),
            isLocked: true,
            isEnabled: true,
            delayMinutes: 1,
            controller: spy
        )

        let status = workflow.statusLine(now: now.addingTimeInterval(61))
        #expect(status?.contains("Privacy & Security") == true)
        #expect(status?.contains("Automation") == true)
        #expect(status?.contains("Curfew") == true)
        #expect(status?.contains("System Events") == true)
    }
}

struct WarningIntervalsPersistenceTests {
    @Test("Warning intervals are normalized and persisted")
    func warningIntervalsPersistNormalized() {
        let suiteName = "CurfewSettingsStoreTests.WarningIntervals.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.warningIntervals = WarningIntervals(
            thirtyMinutes: 10,
            fifteenMinutes: 9,
            fiveMinutes: 8,
            twoMinutes: 7,
            oneMinute: 6
        )
        store.save(settings)

        let loaded = store.load()
        #expect(loaded.warningIntervals == settings.warningIntervals.normalized)
    }
}
