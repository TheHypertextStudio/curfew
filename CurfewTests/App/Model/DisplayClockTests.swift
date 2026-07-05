@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Coverage for the always-on display clock: `beginDisplayClock()` /
/// `displayTick()` advance the observed display (clock, schedule apply,
/// health, transient confirmations) without arming enforcement, so a
/// disarmed app (Debug `just dev`, pre-onboarding, Curfew off) is live but
/// never triggers lockout side-effects. See `CurfewAppModel+DisplayClock.swift`.
@MainActor
struct DisplayClockTests {
    @Test("Display tick refreshes state without arming enforcement side-effects")
    func displayTickRefreshesWithoutEnforcing() {
        let respawnGuard = RecordingRespawnGuard()
        let model = makeModel(respawnGuard: respawnGuard, setupComplete: true)
        // Lock the whole current day so the engine reliably returns `.locked`.
        var schedule = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            schedule.rules[weekday] = DayRule(isDayOff: false, lockMinutes: 0, unlockMinutes: 1439)
        }
        model.lockoutDeadlineStore.clear()
        model.settings.schedule = schedule

        model.displayTick()

        // The display reflects the schedule (state re-derived)…
        #expect(model.state.phase == .locked)
        // …but enforcement is not armed and the enforcement tail never ran, so
        // the respawn guard was neither installed nor armed.
        #expect(model.isEnforcementRunning == false)
        #expect(respawnGuard.callLog.isEmpty)
    }

    @Test("start() arms enforcement; the display clock alone does not")
    func startArmsButDisplayClockDoesNot() {
        let model = makeModel(setupComplete: true)
        model.beginDisplayClock()
        #expect(model.isEnforcementRunning == false)

        model.start()
        #expect(model.isEnforcementRunning == true)
    }

    @Test("Arming catches .dayOff→.locked even when the display clock ran first")
    func armingCatchesTransitionEvenAfterDisplayClockRanFirst() {
        let respawnGuard = RecordingRespawnGuard()
        let model = makeModel(respawnGuard: respawnGuard, setupComplete: true)
        // Lock the whole current day — the exact scenario a release build hits
        // if launched while already inside a lock window.
        var schedule = WeeklySchedule.standardNineToFive
        for weekday in Weekday.allCases {
            schedule.rules[weekday] = DayRule(isDayOff: false, lockMinutes: 0, unlockMinutes: 1439)
        }
        model.lockoutDeadlineStore.clear()
        model.settings.schedule = schedule
        // Hermetic start: force a known `.dayOff` baseline (`seedState` keeps
        // `lastEnforcedPhase` in lockstep) regardless of what the default
        // schedule evaluates to at the moment this test happens to run —
        // otherwise this is a wall-clock-dependent flake.
        model.seedState(CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        ))

        // `CurfewApp.handleInitialLaunch` calls `beginDisplayClock()`
        // unconditionally, then `start()` only if enforcement should arm. Its
        // eager `displayTick()` re-derives `state` to `.locked` here — *before*
        // `start()` ever runs — which previously caused `start()`'s `tick()`
        // to see a no-op transition (previousPhase already `.locked`) and skip
        // arming the respawn guard entirely.
        model.beginDisplayClock()
        #expect(model.state.phase == .locked)
        #expect(respawnGuard.callLog.isEmpty)

        model.start()

        // The armed tick must still detect .dayOff -> .locked (via
        // `lastEnforcedPhase`, seeded at init to .dayOff) and arm the guard —
        // regardless of the display clock having already silently updated
        // `state` first.
        #expect(respawnGuard.callLog.contains("arm"))
    }

    @Test("Display tick applies a due pending schedule change and confirms it")
    func displayTickAppliesDuePendingChange() {
        let model = makeModel(setupComplete: true)
        let past = Date().addingTimeInterval(-60)
        // `.stricter` applies regardless of the current phase (only `.weaker`
        // is held back during lockout), so this is deterministic.
        model.settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: .standardNineToFive,
            requestedAt: past,
            effectiveAt: past,
            classification: .stricter
        )
        #expect(model.pendingScheduleDescription != nil)
        #expect(model.scheduleChangeJustApplied == false)

        model.displayTick()

        #expect(model.settings.pendingScheduleChange == nil)
        #expect(model.scheduleChangeJustApplied == true)
    }

    @Test("Denied→granted Accessibility transition raises the granted confirmation")
    func accessibilityGrantedTransitionFlagsConfirmation() {
        let model = makeModel(
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: false),
            setupComplete: true
        )
        #expect(model.isAccessibilityTrusted == false)
        #expect(model.accessibilityJustGranted == false)

        model.setAccessibilityTrusted(true)
        #expect(model.isAccessibilityTrusted == true)
        #expect(model.accessibilityJustGranted == true)
    }

    // MARK: - Helpers

    private final class AlwaysActiveIdleSource: IdleTimeSource {
        func secondsSinceLastInput() -> TimeInterval {
            0
        }
    }

    private func makeModel(
        respawnGuard: any RespawnGuardControlling = NoOpRespawnGuard(),
        accessibilityAuthorization: AccessibilityAuthorizing = FakeAccessibilityAuthorization(
            trusted: true
        ),
        setupComplete: Bool = false
    ) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let watcher = IdleWatcher(source: AlwaysActiveIdleSource(), idleThresholdSeconds: 300)
        let store = CurfewSettingsStore(defaults: defaults)
        if setupComplete {
            var settings = CurfewSettings.default
            settings.hasCompletedInitialSetup = true
            store.save(settings)
        }
        // Isolated lockout-deadline file so concurrent/sequential test runs
        // cannot share durable state (see `LifecycleWiringTests.makeModel`).
        let deadlineURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-deadline-\(UUID().uuidString).json")
        return CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            featureFlags: .default,
            activityRecorder: NullActivityRecording(),
            idleWatcher: watcher,
            respawnGuard: respawnGuard,
            lockoutDeadlineStore: LockoutDeadlineStore(recordURL: deadlineURL),
            accessibilityAuthorization: accessibilityAuthorization
        )
    }
}
