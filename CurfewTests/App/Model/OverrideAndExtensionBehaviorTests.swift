// Behavior tests for override and extension budget handling.
//
// Grouped here because these tests all exercise the interaction between
// `ExtensionBudgetTracker`, the policy for granting overrides, and the
// event-log side effects. Split out of the original `FeatureBehaviorTests.swift`
// so no single test file exceeds the SwiftLint file-length threshold.

import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct OverrideRequestPolicyTests {
    @Test("Override policy requires 50+ chars and a non-zero budget")
    func overridePolicyValidation() {
        let requestedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let validReason = String(
            repeating: "a",
            count: OverrideRequestPolicy.minimumJustificationCharacters
        )

        #expect(!OverrideRequestPolicy.canConfirm(
            reason: "short",
            overridesRemaining: 1,
            requestedAt: requestedAt,
            now: requestedAt.addingTimeInterval(300)
        ))
        #expect(!OverrideRequestPolicy.canConfirm(
            reason: validReason,
            overridesRemaining: 1,
            requestedAt: requestedAt,
            now: requestedAt.addingTimeInterval(299)
        ))
        #expect(OverrideRequestPolicy.canConfirm(
            reason: validReason,
            overridesRemaining: 1,
            requestedAt: requestedAt,
            now: requestedAt.addingTimeInterval(300)
        ))
        #expect(!OverrideRequestPolicy.canConfirm(
            reason: validReason,
            overridesRemaining: 0,
            requestedAt: requestedAt,
            now: requestedAt.addingTimeInterval(300)
        ))
        #expect(OverrideRequestPolicy.cooldownSeconds == 300)
    }

    @Test("Override defaults align with product settings")
    func overrideDefaults() {
        #expect(CurfewSettings.default.overrideWeeklyLimit == 2)
        #expect(CurfewSettings.default.overrideDurationMinutes == OverrideRequestPolicy
            .defaultOverrideDurationMinutes)
        #expect(CurfewSettings.default.extensionWeeklyLimit == 3)
        #expect(CurfewSettings.default.extensionDurationMinutes == 15)
    }
}

struct OverrideWindowBehaviorTests {
    @Test("Override grants temporary access, then re-locks after expiration")
    func relocksAfterOverrideEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let engine = CurfewEnforcementEngine(calendar: calendar)

        let overrideUntil = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 35))
        )
        let duringOverride = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 5))
        )
        let afterOverride = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 36))
        )

        let duringState = engine.evaluate(
            at: duringOverride,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: overrideUntil
        )
        let afterState = engine.evaluate(
            at: afterOverride,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: overrideUntil
        )

        #expect(duringState.phase != .locked)
        #expect(afterState.phase == .locked)
    }

    @Test("An override past the lock time counts down to its own end and warns first")
    func overrideExpiryWarnsBeforeRelocking() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let engine = CurfewEnforcementEngine(calendar: calendar)
        func at(_ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026, month: 2, day: 2, hour: hour, minute: minute
            )))
        }
        let overrideUntil = try at(19, 0)

        let early = try engine.evaluate(
            at: at(18, 10), schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0, overrideUntil: overrideUntil
        )
        #expect(early.phase == .working)
        #expect(early.minutesRemaining == 50)

        let late = try engine.evaluate(
            at: at(18, 56), schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0, overrideUntil: overrideUntil
        )
        #expect(late.phase == .warning)
        #expect(late.warningStage == .fiveMinutes)
        #expect(late.minutesRemaining == 4)
        #expect(!late.canRequestExtension)
    }

    @Test("An override that ends before the lock time leaves the normal countdown alone")
    func earlyOverrideKeepsScheduleCountdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let engine = CurfewEnforcementEngine(calendar: calendar)
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 2, day: 2, hour: 16, minute: 0
        )))
        let state = engine.evaluate(
            at: now, schedule: .standardNineToFive, extensionMinutesGrantedToday: 0,
            overrideUntil: now.addingTimeInterval(600)
        )
        #expect(state.phase == .working)
        #expect(state.minutesRemaining == 120)
    }
}

struct ExtensionResetConfigurationTests {
    @Test("Default extension reset weekday is Monday")
    func defaultResetWeekdayIsMonday() {
        #expect(CurfewSettings.default.resetWeekday == .monday)
    }

    @Test("Extension budget resets at configured weekday boundary")
    func extensionBudgetResetsOnBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let tracker = ExtensionBudgetTracker(
            weeklyLimit: 1,
            extensionMinutes: 15,
            resetWeekday: .monday,
            calendar: calendar
        )

        let sunday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 12, minute: 0))
        )
        let monday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 12, minute: 0))
        )

        #expect(tracker.requestExtension(at: sunday))
        #expect(tracker.remaining == 0)
        tracker.resetIfNeeded(at: monday)
        #expect(tracker.remaining == 1)
    }
}

@MainActor
struct ExtensionActivationInteractionTests {
    @Test("Hold-confirm extension action consumes budget")
    func holdConfirmConsumesBudget() {
        let model = ModelTestSupport.makeModel()
        model.currentTime = Date()
        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )

        let before = model.extensionsRemaining
        model.confirmExtensionRequest()

        #expect(model.extensionsRemaining == max(0, before - 1))
    }
}

struct OverrideEventStoreTests {
    @Test("Override events append and reload from settings store")
    func overrideEventsPersist() {
        let suiteName = "CurfewSettingsStoreTests.OverrideEvents.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        let event = OverrideEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Device",
            reason: "This is a deliberate override reason with sufficient detail.",
            grantedDurationMinutes: 30
        )
        store.appendOverrideEvent(event)

        let loaded = store.loadOverrideEvents()
        #expect(loaded == [event])
    }
}

@MainActor
struct OverrideEventLoggingTests {
    @Test("Confirming override logs timestamp, device, reason, and duration")
    func confirmOverrideLogsEvent() {
        let suiteName = "CurfewSettingsStoreTests.OverrideLogging.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reason = String(
            repeating: "r",
            count: OverrideRequestPolicy.minimumJustificationCharacters
        )

        model.currentTime = now
        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.overridesRemaining = 1
        model.overrideReasonDraft = reason
        model.overrideRequestedAt = now.addingTimeInterval(-OverrideRequestPolicy.cooldownSeconds)

        model.confirmOverride()

        let event = try? #require(model.overrideEvents.last)
        #expect(event != nil)
        #expect(event?.timestamp == now)
        #expect(event?.reason == reason)
        #expect(event?.grantedDurationMinutes == model.settings.overrideDurationMinutes)
        #expect(!(event?.deviceName.isEmpty ?? true))
        #expect(store.loadOverrideEvents().count == 1)
    }
}
