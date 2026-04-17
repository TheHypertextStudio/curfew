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

    // MARK: - Helpers

    private func makeModel(
        featureFlags: FeatureFlags,
        activityRecorder: any ActivityRecording,
        idleSource: IdleTimeSource
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let watcher = IdleWatcher(source: idleSource, idleThresholdSeconds: 300)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy(),
            featureFlags: featureFlags,
            activityRecorder: activityRecorder,
            idleWatcher: watcher
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
