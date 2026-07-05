import CurfewKit
import Foundation

/// The always-on display clock and the transient confirmation flags it drives.
/// Split from the main class body so the two concerns — "what advances the UI
/// every second" and "what enforcement arming means for `start()`" — read as
/// one cohesive unit, separate from the property bag and init.
@MainActor
extension CurfewAppModel {
    /// Whether enforcement is armed (the full `tick()` runs).
    var isEnforcementRunning: Bool {
        started
    }

    /// Starts the 1 Hz **display clock** — the timer that advances `currentTime`
    /// and re-derives the observed display state every second. Unlike ``start()``
    /// (which *arms enforcement*), this has no onboarding or arming guard and
    /// runs whenever the app has UI, so the countdown, sky, and health stay live
    /// even when Curfew is off or enforcement hasn't armed yet. Idempotent.
    ///
    /// The timer target dispatches to the full ``tick()`` once armed
    /// (`started`), or the side-effect-free ``displayTick()`` while disarmed —
    /// so a disarmed app is live but never locks the Mac.
    func beginDisplayClock() {
        guard timer == nil else { return }
        displayTick()
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(handleTimerFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    /// Guarded `isAccessibilityTrusted` setter — the only place that mutates it.
    /// A denied→granted transition raises the transient "granted" confirmation.
    func setAccessibilityTrusted(_ trusted: Bool) {
        guard isAccessibilityTrusted != trusted else { return }
        let becameGranted = !isAccessibilityTrusted && trusted
        isAccessibilityTrusted = trusted
        if becameGranted { flagAccessibilityGranted() }
    }

    /// The disarmed clock cycle: refresh the display and health with **no**
    /// enforcement side-effects (overlay, key shield, shutdown, notifications,
    /// durable-deadline writes) — so the countdown, sky, and health badge stay
    /// live, and stuck notices clear, without ever locking the Mac.
    func displayTick() {
        refreshDisplayState()
        pollAndUpdateEnforcementHealth()
    }

    /// Advances `currentTime` and re-derives observed display state — the
    /// side-effect-free half shared by ``tick()`` (`+Lifecycle`) and
    /// ``displayTick()``. Runs the engine only once onboarding is complete;
    /// pre-onboarding it leaves `state` at the seeded `.dayOff` while still
    /// advancing the clock.
    func refreshDisplayState() {
        currentTime = Date()

        // Idle sampling lives at the top so downstream surfaces (and any
        // consumers observing `isUserIdle`) see today's true state before the
        // engine runs. `sample()` fires `onIdleStateChanged` only on
        // transitions, so 1 Hz polling costs one CGEventSource read.
        idleWatcher.sample()

        // The app heartbeat (`touchAppHeartbeat()`) is armed-only — it exists
        // for the privileged daemon's durable-deadline shutdown path, which
        // can't fire while disarmed — so it's written from `tick()`, not here.

        if Self.dayToken(for: currentTime) != currentDayToken {
            handleDayRollover(to: Self.dayToken(for: currentTime))
        }

        applyPendingScheduleIfNeeded(now: currentTime)

        extensionTracker.resetIfNeeded(at: currentTime)
        overrideTracker.resetIfNeeded(at: currentTime)
        // Guard writes behind equality checks so an unchanged tick does not fire
        // observation — otherwise every SwiftUI surface bound to the model
        // redraws once per second regardless of whether anything moved.
        if extensionsRemaining != extensionTracker.remaining {
            extensionsRemaining = extensionTracker.remaining
        }
        if overridesRemaining != overrideTracker.remaining {
            overridesRemaining = overrideTracker.remaining
        }

        // Pre-onboarding: keep the seeded `.dayOff` evaluation, but the clock
        // (and thus the time-of-day sky) still advances above.
        guard settings.hasCompletedInitialSetup else { return }

        let newState = enforcementEngine.evaluate(
            at: currentTime,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: extensionMinutesGrantedToday + snoozeMinutesGrantedToday,
            overrideUntil: overrideUntil,
            warningIntervals: settings.warningIntervals,
            workedMinutesToday: workedMinutesToday(at: currentTime)
        )
        if state != newState {
            state = newState
        }
    }

    /// Re-evaluate after a user action that changes enforcement inputs
    /// (extension, snooze, override). Then refreshes the widget's live
    /// snapshot so its deadline reflects the change immediately.
    func refreshAfterUserAction() {
        runTickCycle()
        syncWidgetEnforcementSnapshot()
    }

    /// Timer-target bridge. Swift `Timer` requires a `@objc` selector, and the
    /// tick methods must remain callable from Swift too, so we trampoline here.
    @objc
    func handleTimerFire(_ timer: Timer) {
        runTickCycle()
    }

    /// Runs the full enforcement ``tick()`` once armed, or only the
    /// side-effect-free ``displayTick()`` while disarmed — so acting on a
    /// live-but-disarmed surface (e.g. tapping "extend" while Curfew is off)
    /// never triggers lockout side-effects. Shared by the timer callback and
    /// by user actions that need an immediate re-evaluation.
    private func runTickCycle() {
        if started {
            tick()
        } else {
            displayTick()
        }
    }

    /// Raises the transient "schedule change applied" confirmation. Called
    /// from ``applyPendingScheduleIfNeeded`` at the pending→applied moment.
    func flagScheduleChangeApplied() {
        raiseTransientFlag(
            \.scheduleChangeJustApplied,
            dismissTask: \.scheduleAppliedDismissTask,
            after: 3
        )
    }

    /// Raises the transient "Accessibility granted" confirmation. Called from
    /// ``setAccessibilityTrusted(_:)`` on a denied→granted transition.
    func flagAccessibilityGranted() {
        raiseTransientFlag(
            \.accessibilityJustGranted,
            dismissTask: \.accessibilityGrantedDismissTask,
            after: 2
        )
    }

    /// Sets `flag` true, then clears it after `seconds` unless a fresher call
    /// to this method (for the same `flag`) cancels the wait first. Shared
    /// mechanism behind both transient UI confirmations above: set once,
    /// self-dismiss once, no duplicated cancel/sleep/clear sequence per flag.
    private func raiseTransientFlag(
        _ flag: ReferenceWritableKeyPath<CurfewAppModel, Bool>,
        dismissTask: ReferenceWritableKeyPath<CurfewAppModel, Task<Void, Never>?>,
        after seconds: Double
    ) {
        self[keyPath: flag] = true
        self[keyPath: dismissTask]?.cancel()
        self[keyPath: dismissTask] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?[keyPath: flag] = false
        }
    }
}
