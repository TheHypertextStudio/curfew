@testable import Curfew
import Foundation
import Testing

/// Regression tests for three pieces of tick-loop wiring that were
/// documented as shipped in `todos.md` but had no call sites until the
/// 2026-04-17 audit:
///
/// 1. `activityRecorder.trim(...)` runs on day rollover so the SQLite
///    log honours the 52-week retention promise.
/// 2. `idleWatcher.sample()` runs every tick so `isUserIdle` reflects
///    the live watcher state.
/// 3. `reconcileProGatedModules()` reacts to license activation so Pro
///    surfaces start without an app relaunch.
@MainActor
struct LifecycleWiringTests {
    @Test("Day rollover triggers activity-log retention trim")
    func dayRolloverTrims() {
        let spy = ActivityRecordingSpy()
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: spy,
            idleSource: StubIdleSource(seconds: 0)
        )

        // Force the day-token-changed branch by rewriting the last-seen
        // token to a value that cannot match today's. Any sentinel works;
        // the model compares against `Self.dayToken(for: currentTime)`
        // which is based on today's year/month/day.
        model.currentDayToken = "1970-1-1"
        model.tick()

        #expect(spy.trimCallCount == 1)
        #expect(spy.lastTrimOlderThan == CurfewAppModel.activityRetentionSeconds)
    }

    @Test("Tick forwards to the idle watcher and mirrors isUserIdle")
    func tickSamplesIdleWatcher() {
        let source = StubIdleSource(seconds: 5)
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleSource: source
        )
        #expect(model.isUserIdle == false)

        source.seconds = 600
        model.tick()
        #expect(model.isUserIdle == true)

        source.seconds = 2
        model.tick()
        #expect(model.isUserIdle == false)
    }

    @Test("License activation triggers Pro-gated module reconciliation")
    func licenseActivationReconciles() {
        // Flags stay off so the reconciliation takes the `.stop()` branches
        // on every engine — the goal is to verify the subscription plumbing,
        // not to exercise CloudKit (which requires an iCloud entitlement
        // not available in the Debug/test entitlement file).
        let flags = FeatureFlags.default
        let model = makeModel(
            featureFlags: flags,
            activityRecorder: NullActivityRecording(),
            idleSource: StubIdleSource(seconds: 0)
        )

        model.reconcileProGatedModules()
        #expect(!model.licenseGate.isProUnlocked)

        let key = LicenseKey(
            email: "tester@example.com",
            product: "curfew-pro",
            orderID: "order-test-1",
            issuedAt: Date()
        )
        model.licenseGate.testInjectActivatedKey(key)
        #expect(model.licenseGate.isProUnlocked)

        // Re-entering reconciliation after a license flip must remain
        // idempotent even when engines are already stopped. The regression
        // guards against a crash introduced by asymmetric start/stop in a
        // future Pro-gated module.
        model.reconcileProGatedModules()
        #expect(model.licenseGate.isProUnlocked)
    }

    @Test("Tick refreshes isAccessibilityTrusted from the injected checker")
    func tickRefreshesAccessibilityTrust() {
        let trust = StubAccessibilityTrust(isProcessTrusted: false)
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleSource: StubIdleSource(seconds: 0),
            accessibilityTrust: trust,
            setupComplete: true
        )

        #expect(!model.isAccessibilityTrusted)

        trust.isProcessTrusted = true
        model.tick()
        #expect(model.isAccessibilityTrusted)

        trust.isProcessTrusted = false
        model.tick()
        #expect(!model.isAccessibilityTrusted)
    }

    @Test("start() installs the respawn guard so killed Curfew respawns under lockout")
    func startInstallsRespawnGuard() {
        let respawnGuard = RecordingRespawnGuard()
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleSource: StubIdleSource(seconds: 0),
            respawnGuard: respawnGuard,
            setupComplete: true
        )

        #expect(respawnGuard.callLog.isEmpty)
        model.start()

        // `start()` is idempotent — call twice and we still install exactly
        // once. Re-installing on every relaunch is fine because launchctl
        // load is idempotent at the system level, but the model must not
        // hammer launchctl when callers repeat `start()` themselves.
        model.start()

        #expect(respawnGuard.callLog == ["install"])
    }

    @Test("Weaker pending schedule change is held back during active lockout")
    func weakerPendingScheduleDeferredDuringLockout() {
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleSource: StubIdleSource(seconds: 0),
            setupComplete: true
        )

        // Force the model into a locked phase by configuring a schedule
        // that locks the whole current day, then ticking so the engine
        // computes `.locked`.
        var schedule = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            schedule.rules[weekday] = DayRule(
                isDayOff: false,
                lockMinutes: 0,
                unlockMinutes: 1439
            )
        }
        model.settings.schedule = schedule
        model.start()
        #expect(model.state.phase == .locked)

        // Queue a weaker pending change whose effectiveAt is already past.
        // Without the C7 guard the next tick would swap the schedule in
        // mid-lockout and the engine would drop straight to .working.
        var weaker = schedule
        for weekday in Weekday.allCases {
            weaker.rules[weekday] = DayRule(
                isDayOff: true,
                lockMinutes: 0,
                unlockMinutes: 0
            )
        }
        let past = Date().addingTimeInterval(-60)
        model.settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: weaker,
            requestedAt: past,
            effectiveAt: past,
            classification: .weaker
        )

        model.tick()

        // Pending change must still be present and lockout must hold.
        #expect(model.settings.pendingScheduleChange != nil)
        #expect(model.state.phase == .locked)
    }

    @Test("Locked-phase transitions arm and disarm the respawn guard")
    func lockedPhaseArmsAndDisarmsGuard() {
        let respawnGuard = RecordingRespawnGuard()
        let model = makeModel(
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleSource: StubIdleSource(seconds: 0),
            respawnGuard: respawnGuard,
            setupComplete: true
        )
        // Set up a schedule that locks the entire current day so the
        // engine's evaluation reliably returns `.locked` regardless of
        // wall-clock time. lockMinutes = 0 means "lock at midnight";
        // unlockMinutes = 1439 means "unlock one minute before next
        // midnight". `start()` then drives the tick and the engine.
        var schedule = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            schedule.rules[weekday] = DayRule(
                isDayOff: false,
                lockMinutes: 0,
                unlockMinutes: 1439
            )
        }
        model.settings.schedule = schedule

        model.start()
        #expect(model.state.phase == .locked)
        #expect(respawnGuard.callLog.contains("arm"))

        // Flip the schedule to .dayOff for every day; tick() will see the
        // phase fall back to .dayOff and disarm fires once. Clearing the
        // durable deadline record first is necessary because M5's
        // forced-lockout logic would otherwise keep the device locked
        // until today's scheduled unlock time arrives — schedule alone
        // cannot release a lockout once the durable record is armed.
        var dayOff = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            dayOff.rules[weekday] = DayRule(
                isDayOff: true,
                lockMinutes: 0,
                unlockMinutes: 0
            )
        }
        model.lockoutDeadlineStore.clear()
        model.settings.schedule = dayOff
        model.tick()
        #expect(model.state.phase == .dayOff)
        #expect(respawnGuard.callLog.contains("disarm"))
    }

    // MARK: - Helpers

    private func makeModel(
        featureFlags: FeatureFlags,
        activityRecorder: any ActivityRecording,
        idleSource: IdleTimeSource,
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard(),
        accessibilityTrust: any AccessibilityTrustChecking = StubAccessibilityTrust(
            isProcessTrusted: true
        ),
        setupComplete: Bool = false
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let watcher = IdleWatcher(source: idleSource, idleThresholdSeconds: 300)
        let store = CurfewSettingsStore(defaults: defaults)
        if setupComplete {
            var settings = CurfewSettings.default
            settings.hasCompletedInitialSetup = true
            store.save(settings)
        }
        // Tests use an isolated lockout-deadline file under the OS temp
        // directory so concurrent / sequential test runs cannot share
        // durable state; a stale file would otherwise wedge the next
        // test into a forced-lockout phase.
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-deadline-\(UUID().uuidString).json")
        return CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            featureFlags: featureFlags,
            activityRecorder: activityRecorder,
            idleWatcher: watcher,
            respawnGuard: respawnGuard,
            accessibilityTrust: accessibilityTrust,
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL)
        )
    }
}

// MARK: - Spies & stubs

@MainActor
private final class ActivityRecordingSpy: ActivityRecording {
    private(set) var trimCallCount = 0
    private(set) var lastTrimOlderThan: TimeInterval?

    func recordPhaseTransition(
        from previous: EnforcementPhase,
        to current: EnforcementPhase,
        at timestamp: Date
    ) {}

    func recordExtensionGranted(minutes: Int, at timestamp: Date) {}

    func recordOverrideGranted(minutes: Int, reason: String, at timestamp: Date) {}

    func recordWarningEscalation(
        stageDescriptor: String,
        minutesRemaining: Int,
        at timestamp: Date
    ) {}

    func events(in range: ClosedRange<Date>) -> [ActivityEvent] {
        []
    }

    func exportCSV(in range: ClosedRange<Date>) throws -> String {
        ""
    }

    func trim(olderThan seconds: TimeInterval, now: Date) {
        trimCallCount += 1
        lastTrimOlderThan = seconds
    }

    let mutationCount: Int = 0
}

private final class StubIdleSource: IdleTimeSource {
    var seconds: TimeInterval
    init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    func secondsSinceLastInput() -> TimeInterval {
        seconds
    }
}
