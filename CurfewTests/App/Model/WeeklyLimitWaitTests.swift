@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// Raising a weekly limit waits like loosening the schedule; until the raise
/// applies, everything that enforces or reports a limit uses the value in
/// force. Models here never show a window: overlays are suppressed in the
/// test host, the keyboard shield is a spy and the Curfew helper is disabled.
@MainActor
struct WeeklyLimitWaitTests {
    private let calendar = Calendar.current
    private static let day: TimeInterval = 24 * 60 * 60

    /// Monday 16 November 2026 unless `day` says otherwise.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        ))!
    }

    private final class Clock {
        var now: Date
        init(_ now: Date) {
            self.now = now
        }
    }

    private static func store(setupComplete: Bool = true, consent: Bool = true)
        -> CurfewSettingsStore {
        let defaults = UserDefaults(suiteName: "WeeklyLimitWaitTests.\(UUID().uuidString)")!
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.hasCompletedInitialSetup = setupComplete
        settings.autoShutdownEnabled = false
        settings.extensionWeeklyLimit = 3
        settings.extensionDurationMinutes = 15
        settings.overrideWeeklyLimit = 2
        settings.overrideDurationMinutes = 30
        settings.resetWeekday = .monday
        for day in Weekday.allCases {
            settings.schedule.rules[day] = DayRule(
                isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 7 * 60
            )
        }
        store.save(settings)
        store.saveAutomaticScheduleConsent(consent)
        return store
    }

    private func model(
        _ clock: Clock,
        store: CurfewSettingsStore? = nil,
        runtime: EnforcementRuntimeStateStore = EnforcementRuntimeStateStore()
    ) -> CurfewAppModel {
        let model = CurfewAppModel(
            settingsStore: store ?? Self.store(), appRouter: AppRouterSpy(), flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false, cloudSyncEnabled: false, mcpServerEnabled: false,
                privilegedHelperEnabled: false, calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true),
            keyboardShield: KeyboardShieldSpy(),
            runtimeStateStore: runtime,
            runtimeNow: clock.now, enforcementClock: { clock.now }
        )
        model.displayTick()
        return model
    }

    // MARK: - Raise waits, lower applies

    @Test("Raising more time at 5:55 PM leaves tonight's allowance where it was")
    func raiseWaits() throws {
        let clock = Clock(at(17, 55))
        let model = model(clock)
        model.requestLimit(.extensionCount, value: 20)
        #expect(model.settings.extensionWeeklyLimit == 3)
        #expect(model.extensionsRemaining == 3)
        #expect(model.extensionTracker.weeklyLimit == 3)
        #expect(model.requestedLimit(.extensionCount) == 20)
        let pending = try #require(model.settings.pendingLimitChange(for: .extensionCount))
        #expect(pending.effectiveAt == model.policyEngine.earliestEffectiveDate(
            for: .weaker, requestedAt: at(17, 55)
        ))
    }

    @Test("Lowering applies at once and clears the raise that was waiting")
    func lowerApplies() {
        let clock = Clock(at(12))
        let model = model(clock)
        model.requestLimit(.extensionCount, value: 8)
        model.requestLimit(.extensionCount, value: 1)
        #expect(model.settings.extensionWeeklyLimit == 1)
        #expect(model.extensionsRemaining == 1)
        #expect(model.settings.pendingLimitChanges.isEmpty)
    }

    @Test("Asking again replaces the waiting raise; asking for the value in force cancels it")
    func replaceAndCancel() throws {
        let clock = Clock(at(12))
        let model = model(clock)
        model.requestLimit(.overrideMinutes, value: 45)
        clock.now = at(13)
        model.displayTick()
        model.requestLimit(.overrideMinutes, value: 60)
        let pending = try #require(model.settings.pendingLimitChange(for: .overrideMinutes))
        #expect(pending.value == 60)
        #expect(pending.effectiveAt == at(13).addingTimeInterval(Self.day))
        model.cancelPendingLimit(.overrideMinutes)
        #expect(model.settings.pendingLimitChanges.isEmpty)
        #expect(model.settings.overrideDurationMinutes == 30)
    }

    // MARK: - Every reader uses the value in force

    @Test("More time, MCP, the override and the widget all use the limits in force")
    func everyReaderUsesValueInForce() throws {
        let clock = Clock(at(17, 50))
        let model = model(clock)
        defer { model.stopEnforcementForUninstall() }
        model.requestLimit(.extensionCount, value: 10)
        model.requestLimit(.extensionMinutes, value: 60)
        model.requestLimit(.overrideCount, value: 10)
        model.requestLimit(.overrideMinutes, value: 60)
        model.start()
        try #require(model.state.canRequestExtension)

        // Today's more time button and its count.
        #expect(model.todayPresentation.moreTime == .available(extensionsLeft: 3))
        model.confirmExtensionRequest()
        #expect(model.extensionMinutesGrantedToday == 15)
        #expect(model.extensionsRemaining == 2)

        // The assistant path through MCP.
        #expect(model.applyMCPAction(MCPPendingRequest(
            tool: .requestExtension, argumentsJSON: "{}"
        )))
        #expect(model.extensionMinutesGrantedToday == 30)
        #expect(model.extensionsRemaining == 1)

        // The widget's settings snapshot.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-limit-widget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let widget = WidgetSharedStateStore(
            settingsURL: directory.appendingPathComponent("settings.json"),
            enforcementURL: directory.appendingPathComponent("enforcement.json")
        )
        try widget.sync(settings: model.settings)
        let mirrored = widget.loadSettings()
        #expect(mirrored.extensionWeeklyLimit == 3)
        #expect(mirrored.extensionDurationMinutes == 15)
        #expect(mirrored.overrideWeeklyLimit == 2)
        #expect(mirrored.overrideDurationMinutes == 30)

        // The lock's override.
        clock.now = at(19)
        model.tick()
        try #require(model.state.phase == .locked)
        #expect(model.overridesRemaining == 2)
        model.beginOverrideRequest()
        model.overrideReasonDraft = String(repeating: "a", count: 60)
        clock.now = at(19, 6)
        model.tick()
        model.confirmOverride()
        #expect(model.overridesRemaining == 1)
        #expect(model.overrideUntil == at(19, 6).addingTimeInterval(30 * 60))
        #expect(model.overrideEvents.last?.grantedDurationMinutes == 30)
    }

    // MARK: - No path applies a raise early

    @Test("A waiting raise survives relaunch and applies only when its time comes")
    func relaunch() {
        let clock = Clock(at(17, 55))
        let store = Self.store()
        let runtime = EnforcementRuntimeStateStore()
        let first = model(clock, store: store, runtime: runtime)
        first.requestLimit(.overrideCount, value: 6)

        clock.now = at(18, 30)
        let second = model(clock, store: store, runtime: runtime)
        #expect(second.settings.overrideWeeklyLimit == 2)
        #expect(second.overridesRemaining == 2)
        #expect(second.settings.pendingLimitChange(for: .overrideCount)?.value == 6)

        clock.now = at(17, 54, day: 17)
        second.displayTick()
        #expect(second.overridesRemaining == 2)
        clock.now = at(17, 55, day: 17)
        second.displayTick()
        #expect(second.settings.overrideWeeklyLimit == 6)
        #expect(second.overridesRemaining == 6)
        #expect(second.settings.pendingLimitChanges.isEmpty)

        let third = model(clock, store: store, runtime: runtime)
        #expect(third.settings.overrideWeeklyLimit == 6)
    }

    @Test("Setting the clock back does nothing; setting it forward during the lock is held")
    func clockChanges() {
        let clock = Clock(at(17, 55))
        let model = model(clock)
        defer { model.stopEnforcementForUninstall() }
        model.start()
        model.requestLimit(.extensionCount, value: 10)

        clock.now = at(12, day: 9)
        model.tick()
        #expect(model.settings.extensionWeeklyLimit == 3)
        #expect(model.settings.pendingLimitChange(for: .extensionCount)?.effectiveAt ==
            at(17, 55).addingTimeInterval(Self.day))

        // Two days ahead at 11 PM: well past the cooldown, but inside the lock.
        clock.now = at(23, day: 18)
        model.tick()
        #expect(model.state.phase == .locked)
        model.tick()
        #expect(model.settings.extensionWeeklyLimit == 3)
        #expect(model.extensionsRemaining == 3)

        clock.now = at(8, day: 19)
        model.tick()
        model.tick()
        #expect(model.settings.extensionWeeklyLimit == 10)
    }

    @Test("The weekly refill uses the limit in force, not the one waiting")
    func weekRollover() throws {
        let clock = Clock(at(12, day: 22))
        let model = model(clock)
        model.confirmExtensionRequestForTesting()
        model.requestLimit(.extensionCount, value: 9)

        clock.now = at(8, day: 23)
        model.displayTick()
        #expect(model.extensionTracker.usedCount == 0)
        #expect(model.extensionsRemaining == 3)
        #expect(model.settings.extensionWeeklyLimit == 3)
        #expect(try #require(model.settings.pendingLimitChange(for: .extensionCount)).value == 9)
    }

    @Test("Turning the weekly schedule off does not let a raise skip the wait")
    func scheduleOff() {
        let clock = Clock(at(12))
        let model = model(clock, store: Self.store(consent: false))
        #expect(!model.automaticScheduleEnabled)
        model.requestLimit(.overrideMinutes, value: 60)
        #expect(model.settings.overrideDurationMinutes == 30)
        #expect(model.settings.pendingLimitChange(for: .overrideMinutes) != nil)
    }

    @Test("During setup a raise applies at once, as a schedule edit does")
    func duringSetup() {
        let clock = Clock(at(12))
        let model = model(clock, store: Self.store(setupComplete: false))
        model.requestLimit(.overrideCount, value: 5)
        #expect(model.settings.overrideWeeklyLimit == 5)
        #expect(model.overridesRemaining == 5)
    }

    @Test("A raise synced from another Mac waits on this one")
    func syncedRaiseWaits() {
        let clock = Clock(at(17, 55))
        let model = model(clock)
        var remote = model.settings
        remote.extensionWeeklyLimit = 20
        remote.overrideDurationMinutes = 480
        model.cloudKitSyncEngine.onSettingsReceived?(remote)
        #expect(model.settings.extensionWeeklyLimit == 3)
        #expect(model.settings.overrideDurationMinutes == 30)
        #expect(model.extensionsRemaining == 3)
        #expect(model.settings.pendingLimitChange(for: .extensionCount)?.value == 20)
    }

    // MARK: - Wording

    @Test("The row says what is waiting, when it applies and what stands until then")
    func wording() {
        let clock = Clock(at(17, 55))
        let model = model(clock)
        #expect(model.pendingLimitDescription(for: .extensionCount) == nil)
        model.requestLimit(.extensionCount, value: 20)
        model.requestLimit(.overrideMinutes, value: 60)
        let when = at(17, 55, day: 17)
        let day = when.formatted(.dateTime.month(.abbreviated).day())
        let time = when.formatted(date: .omitted, time: .shortened)
        #expect(model.pendingLimitDescription(for: .extensionCount) ==
            "Goes up to 20 on \(day) at \(time). Until then, 3 stands.")
        #expect(model.pendingLimitDescription(for: .overrideMinutes) ==
            "Goes up to 60 min on \(day) at \(time). Until then, 30 min stands.")
    }
}

private extension CurfewAppModel {
    /// Spends one extension outside the warning window, so a test can show a
    /// weekly refill happened without arming enforcement.
    func confirmExtensionRequestForTesting() {
        _ = grantPersistentExtension()
    }
}
