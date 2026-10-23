@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// Injected presentation effects only. These tests never construct native power or XPC.
@MainActor
struct SunriseModelLifecycleTests {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func calendar() -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return result
    }

    private func preferences(enabled: Bool = true, battery: Bool = false)
        -> RestAppearancePreferences {
        RestAppearancePreferences(
            sunriseWakeEnabled: enabled, sunriseOnBatteryEnabled: battery
        )
    }

    private func model(demo: Bool = false) throws -> CurfewAppModel {
        let suite = "SunriseModelLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.schedule = .tenToSix
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store, appRouter: AppRouterSpy(), flavor: .current,
            isDemoSession: demo,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false, cloudSyncEnabled: false, mcpServerEnabled: false,
                privilegedHelperEnabled: false, calendarEnabled: false
            ),
            activityRecorder: NullActivityRecording(),
            licenseGate: LicenseGate(defaults: defaults),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accountWakeLedgerStore: AccountWakeLedgerStore(recordURL: FileManager.default
                .temporaryDirectory.appendingPathComponent("sunrise-ledger-\(UUID()).json"))
        )
        model.automaticScheduleEnabled = false
        model.currentTime = date("2026-10-19T12:00:00-07:00")
        model.sunriseCalendar = calendar()
        model.restAppearance = preferences()
        return model
    }

    private func inject(_ effects: Effects, into model: CurfewAppModel) {
        model.sunriseWakeCoordinator = effects.coordinator
        model.sunriseOnExternalPower = { effects.externalPower }
    }

    @Test("A local Sunrise schedules before enforcement or automatic lockout is enabled")
    func schedulesWithoutEnforcement() async throws {
        let model = try model()
        let effects = Effects()
        inject(effects, into: model)
        #expect(!model.isEnforcementRunning)
        #expect(!model.automaticScheduleEnabled)
        #expect(model.lockoutDeadlineStore.load() == nil)
        await model.reconcileSunriseWake()
        let plan = try #require(effects.plans.first)
        #expect(plan.owner == CurfewFlavor.current.daemonLabel + ".sunrise")
        #expect(plan.wakeAt == date("2026-10-20T05:30:00-07:00"))
        #expect(plan.holdUntil == date("2026-10-20T06:05:00-07:00"))
        #expect(model.sunriseStatus == .scheduled)
        #expect(model.lockoutDeadlineStore.load() == nil)
    }

    @Test("An unlimited account restriction cannot move Sunrise or release authority")
    func strongerRestrictionKeepsScheduledUnlock() async throws {
        let model = try model()
        let effects = Effects()
        inject(effects, into: model)
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: model.currentTime.addingTimeInterval(-3600),
            scheduledUnlockAt: .distantFuture, kind: .accountWakeCampaign,
            campaignID: UUID()
        )
        model.lockoutDeadlineStore.save(record)
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .none, minutesRemaining: .max,
            canRequestExtension: false, lockDate: record.lockoutStartedAt,
            unlockDate: .distantFuture
        )
        let previous = model.state
        await model.reconcileSunriseWake()
        let plan = try #require(effects.plans.first)
        #expect(plan.wakeAt == date("2026-10-20T05:30:00-07:00"))
        #expect(plan.holdUntil == date("2026-10-20T06:05:00-07:00"))
        #expect(model.lockoutDeadlineStore.load() == record)
        #expect(model.state == previous)
    }

    @Test("Starting or skipping the morning reflection releases this Sunrise hold")
    func morningDismissalReleasesHold() async throws {
        for skipped in [false, true] {
            let model = try model()
            let effects = Effects()
            let plan = try scheduledPlan(for: model)
            inject(effects, into: model)
            model.currentTime = plan.wakeAt
            model.reflectionState.isDaybreakPresented = true
            await model.reconcileSunriseWake()
            try #require(effects.delivery.isActive)
            if skipped {
                model.skipReflection(gate: .morning)
            } else {
                model.saveReflection(gate: .morning, answers: [])
            }
            #expect(!effects.delivery.isActive)
            await model.reconcileSunriseWake()
            #expect(!effects.delivery.isActive)
            #expect(effects.calls.filter { $0 == "acquire" }.count == 1)
        }
    }

    @Test("Disabling Sunrise cancels the owned future plan through the injected coordinator")
    func disablingCancelsFuturePlan() async throws {
        let model = try model()
        let effects = Effects()
        let plan = try scheduledPlan(for: model)
        await effects.coordinator.reconcile(
            plan: plan, enabled: true, onExternalPower: true, now: model.currentTime
        )
        effects.calls.removeAll()
        inject(effects, into: model)
        model.restAppearance = preferences(enabled: false)
        await model.reconcileSunriseWake()
        #expect(effects.calls.contains("cancel"))
        #expect(model.sunriseStatus == .disabled)
    }

    @Test("Disabling Sunrise releases an active bounded display assertion")
    func disablingReleasesDisplay() async throws {
        let model = try model()
        let effects = Effects()
        let plan = try scheduledPlan(for: model)
        await effects.coordinator.reconcile(
            plan: plan, enabled: true, onExternalPower: true, now: plan.wakeAt
        )
        try #require(effects.delivery.isActive)
        effects.calls.removeAll()
        inject(effects, into: model)
        model.currentTime = plan.wakeAt
        model.restAppearance = preferences(enabled: false)
        await model.reconcileSunriseWake()
        #expect(!effects.delivery.isActive)
        #expect(effects.calls.contains("release"))
        #expect(effects.calls.contains("cleanup"))
        #expect(model.sunriseStatus == .disabled)
    }

    @Test("Battery exclusion remains visible instead of silently scheduling an AC-only plan")
    func batteryExclusion() async throws {
        let model = try model()
        let effects = Effects()
        effects.externalPower = false
        inject(effects, into: model)
        await model.reconcileSunriseWake()
        #expect(model.sunriseStatus == .batteryExcluded)
        #expect(effects.plans.isEmpty)
        #expect(!effects.calls.contains("activity"))
    }

    @Test("Helper unavailability remains distinct from a rejected request")
    func helperFailureStatus() async throws {
        for (failure, status) in [
            (
                SunriseWakeCoordinator.HelperFailure.unavailable,
                SunriseWakeCoordinator.Status.helperUnavailable
            ),
            (.rejected, .requestRejected)
        ] {
            let model = try model()
            let effects = Effects()
            effects.replaceFailure = failure
            inject(effects, into: model)
            await model.reconcileSunriseWake()
            #expect(model.sunriseStatus == status)
        }
    }

    @Test("Debug demo sessions stay disarmed even when fake runtime effects are injected")
    func demoNeverRequestsWake() async throws {
        let model = try model(demo: true)
        try #require(model.isDemoSession)
        let effects = Effects()
        inject(effects, into: model)
        await model.reconcileSunriseWake()
        #expect(effects.calls.isEmpty)
        #expect(model.sunriseStatus == .disabled)
    }

    @Test("An uncomposed runtime remains inert and never constructs native effects")
    func noRuntimeRemainsInert() async throws {
        let model = try model()
        #expect(model.sunriseWakeCoordinator == nil)
        await model.reconcileSunriseWake()
        #expect(model.sunriseWakeCoordinator == nil)
        #expect(model.sunriseStatus == .disabled)
    }

    private func scheduledPlan(for model: CurfewAppModel) throws -> SunriseWakePlan {
        try #require(SunriseWakePlanner(owner: CurfewFlavor.current.daemonLabel + ".sunrise")
            .presentationPlan(
                schedule: model.settings.schedule, appearance: model.restAppearance,
                at: model.currentTime, calendar: model.sunriseCalendar
            ))
    }

    @MainActor
    private final class Effects {
        var externalPower = true
        var calls: [String] = []
        var plans: [SunriseWakePlan] = []
        var replaceFailure: SunriseWakeCoordinator.HelperFailure?
        lazy var delivery = SunriseDisplayDelivery(
            declareUserActivity: { self.calls.append("activity") },
            acquireDisplayAssertion: { _ in
                self.calls.append("acquire")
                return .init(rawValue: 1)
            },
            releaseDisplayAssertion: { _ in self.calls.append("release") }
        )
        lazy var coordinator = SunriseWakeCoordinator(
            operations: .init(
                replace: { plan in
                    if let failure = self.replaceFailure {
                        throw failure
                    }
                    self.calls.append("replace")
                    self.plans.append(plan)
                },
                cancel: { self.calls.append("cancel") }
            ),
            displayDelivery: delivery,
            cleanupNativeAssertions: { self.calls.append("cleanup") }
        )
    }
}

extension SunriseModelLifecycleTests {
    @Test("The all-day companion resolves a local night even when automatic wake is off")
    func companionNightWithoutWake() throws {
        let model = try model()
        model.restAppearance = preferences(enabled: false)
        model.currentTime = date("2026-10-19T23:00:00-07:00")
        let snapshot = model.restCompanionSnapshot
        #expect(snapshot.lockDate == date("2026-10-19T22:00:00-07:00"))
        #expect(snapshot.unlockDate == date("2026-10-20T06:00:00-07:00"))
        #expect(snapshot.expiresAt == date("2026-10-20T07:00:00-07:00"))
        #expect(snapshot.appearance == model.restAppearance)
        #expect(!model.isEnforcementRunning)
    }

    @Test("Companion occurrence expiry is stable across ticks and retains scheduled morning")
    func companionStableMorning() throws {
        let model = try model()
        model.currentTime = date("2026-10-20T06:10:00-07:00")
        let morning = model.restCompanionSnapshot
        model.currentTime = model.currentTime.addingTimeInterval(1)
        #expect(model.restCompanionSnapshot == morning)
        #expect(morning.unlockDate == date("2026-10-20T06:00:00-07:00"))
        #expect(morning.resolve(at: model.currentTime, timeZone: .current).phase == .morning)
        model.currentTime = date("2026-10-20T07:00:00-07:00")
        let next = model.restCompanionSnapshot
        #expect(next.unlockDate == date("2026-10-21T06:00:00-07:00"))
        #expect(next.resolve(at: model.currentTime, timeZone: .current).phase == .allDay)
    }

    @Test("A remote restriction cannot invent a companion occurrence on days off")
    func companionHasNoRemoteAuthority() throws {
        let model = try model()
        model.settings.schedule = .allDaysOff
        model.state = CurfewEvaluation(
            phase: .locked, warningStage: .none, minutesRemaining: .max,
            canRequestExtension: false, lockDate: model.currentTime,
            unlockDate: .distantFuture
        )
        let snapshot = model.restCompanionSnapshot
        #expect(snapshot.lockDate == nil)
        #expect(snapshot.unlockDate == nil)
        model.currentTime = model.currentTime.addingTimeInterval(100)
        #expect(model.restCompanionSnapshot == snapshot)
        #expect(snapshot.resolve(at: model.currentTime, timeZone: .current).phase == .allDay)
        #expect(model.state.unlockDate == .distantFuture)
    }
}
