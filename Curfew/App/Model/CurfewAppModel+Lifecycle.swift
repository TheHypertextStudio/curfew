import Combine
import EventKit
import Foundation
import OSLog
import UserNotifications
import WidgetKit

/// Engine-side internals of `CurfewAppModel` — the tick loop plus the
/// private helpers translating engine output into published state.
/// Split from actions/presentation so "why did lockout fire early?"
/// has one obvious file to open.
@MainActor
extension CurfewAppModel {
    /// One enforcement cycle. Invoked by the 1 Hz timer and opportunistically
    /// after user actions that should take effect immediately (extension
    /// grant, override confirm, schedule swap).
    ///
    /// The order of operations within a tick matters:
    /// 1. Capture `previousPhase` before mutating `state`, so the transition
    ///    detector at the bottom can notice `working → locked`.
    /// 2. Refresh `currentTime` *once* so every downstream consumer agrees
    ///    on "now" for this tick.
    /// 3. Detect day rollover and reset daily grants (extension minutes,
    ///    snoozes) — must happen before the engine runs, else we'd count
    ///    yesterday's extensions against today.
    /// 4. Apply any pending schedule swap whose effective date has arrived.
    /// 5. Reset weekly budgets if the reset weekday has arrived.
    /// 6. Run the enforcement engine to produce a fresh evaluation.
    /// 7. Propagate derived effects: rotate lockout copy, toggle override
    ///    composer, fire warnings, toggle key tap, shutdown, overlays.
    func tick() {
        let previousPhase = state.phase
        currentTime = Date()

        // Idle sampling lives at the top of the tick so downstream surfaces
        // (and any consumers observing `isUserIdle`) see today's true state
        // before the engine runs. `sample()` fires `onIdleStateChanged`
        // only on transitions, so 1 Hz polling costs one CGEventSource read.
        idleWatcher.sample()

        // Refresh the Accessibility-trust banner state. Polling once per
        // tick keeps the UI live: when the user grants the permission in
        // System Settings the banner clears within a second without the
        // app needing a foreground notification subscription. Equality
        // guard prevents `objectWillChange` churn when the value is stable.
        let trusted = accessibilityTrust.isProcessTrusted
        if isAccessibilityTrusted != trusted {
            setAccessibilityTrusted(trusted)
        }
        // Touch the heartbeat file so the privileged daemon can tell
        // whether the app is still running. Stale heartbeat plus an
        // active durable deadline drives the daemon's shutdown path.
        touchAppHeartbeat()

        if Self.dayToken(for: currentTime) != currentDayToken {
            handleDayRollover(to: Self.dayToken(for: currentTime))
        }

        applyPendingScheduleIfNeeded(now: currentTime)

        extensionTracker.resetIfNeeded(at: currentTime)
        overrideTracker.resetIfNeeded(at: currentTime)
        // Guard `@Published` writes behind equality checks so an unchanged
        // tick does not fire `objectWillChange` — otherwise every SwiftUI
        // surface bound to the model redraws once per second regardless of
        // whether anything it displays actually moved.
        if extensionsRemaining != extensionTracker.remaining {
            extensionsRemaining = extensionTracker.remaining
        }
        if overridesRemaining != overrideTracker.remaining {
            overridesRemaining = overrideTracker.remaining
        }

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
        // Durable-deadline enforcement may swap `state` back to `.locked`
        // if the engine dropped lockout early (clock skew, schedule
        // weakening past the cooldown, or a manual record left from a
        // prior session). It runs after the engine assignment so any
        // change here is reflected in `propagatePhaseTransition` below.
        reconcileDurableLockoutDeadline()

        propagatePhaseTransition(from: previousPhase)
        writeDurableDeadlineIfEnteringLockout(previousPhase: previousPhase)

        activityRecorder.recordPhaseTransition(
            from: previousPhase,
            to: state.phase,
            at: currentTime
        )
        reconcileOverrideComposerState(previousPhase: previousPhase)
        notificationManager.update(
            stage: state.warningStage,
            now: currentTime,
            alreadyFiredElsewhere: warningStagesFiredToday
        )
        recordWarningStageFiringIfNeeded()
        updateLockoutInterception(for: state.phase)
        updateShutdownWorkflow()
        overlayCoordinator.updateOverlays(for: state, model: self, lockoutMessage: lockoutMessage)
        checkCalendarCurfewOverlap()
    }

    private func propagatePhaseTransition(from previousPhase: EnforcementPhase) {
        if previousPhase != .locked, state.phase == .locked {
            lockoutMessage = EncouragementMessageCatalog.next(after: lockoutMessage)
        }
        // Publish the current lockout/warning snapshot so other devices
        // can align. Writing on every transition (not every tick) keeps
        // CloudKit churn minimal; null-out warningPhaseStarted when we
        // drop out of warning so joining devices don't see stale data.
        if previousPhase != state.phase {
            publishLockoutStateIfSyncActive(previous: previousPhase)
        }
        // Reload widget timelines on both phase transitions and warning-
        // stage transitions. The old behaviour only covered phase, so a
        // widget viewed during warning escalation stayed on stale copy
        // until the lockout moment. Per-stage reloads keep the ring and
        // the label in sync with what the app thinks is happening.
        if featureFlags.widgetKitEnabled,
           previousPhase != state.phase || previousWarningStage != state.warningStage {
            WidgetCenter.shared.reloadTimelines(ofKind: CurfewWidgetIdentity.kind)
        }
        previousWarningStage = state.warningStage
        if previousPhase != state.phase, featureFlags.privilegedHelperEnabled {
            if state.phase == .locked {
                LockoutStatePersistence.markLockoutActive()
            } else if previousPhase == .locked {
                LockoutStatePersistence.markLockoutInactive()
            }
        }
        toggleRespawnGuardIfPhaseChanged(previousPhase: previousPhase)
        if previousPhase != state.phase {
            syncWidgetEnforcementSnapshot()
        }
    }

    /// Fires one notification per event when a calendar event starts
    /// within 60 min of the curfew gate during working/warning phases.
    /// No-ops when calendar is off, Pro isn't unlocked, no event is
    /// in the window, or we've already prompted for this event today.
    func checkCalendarCurfewOverlap() {
        guard featureFlags.calendarEnabled, licenseGate.isProUnlocked else { return }
        guard state.phase == .working || state.phase == .warning else { return }

        let todayRule = settings.schedule.rule(for: Weekday(from: currentTime))
        guard !todayRule.isDayOff else { return }

        guard let event = calendarMonitor.eventNearingCurfew(
            scheduleEndMinutes: todayRule.lockMinutes,
            now: currentTime
        ) else { return }

        let eventID = event.eventIdentifier ?? event.title ?? ""
        guard eventID != curfewOverlapPromptFiredForEventID else { return }
        curfewOverlapPromptFiredForEventID = eventID

        let content = UNMutableNotificationContent()
        content.title = "Meeting near curfew"
        let title = event.title ?? "A meeting"
        let startText = event.startDate.map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? "soon"
        content.body = "\(title) starts at \(startText). "
            + "Request an extension before curfew fires."
        content.categoryIdentifier = "CALENDAR_OVERLAP"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "curfew.calendar-overlap.\(eventID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Hides the Convince Me composer on lockout exit and shows it on
    /// lockout entry once the cooldown elapses. Ticks after engine eval.
    func reconcileOverrideComposerState(previousPhase: EnforcementPhase) {
        if previousPhase == .locked, state.phase != .locked {
            overrideCooldownEndsAt = nil
            isOverrideComposerVisible = false
            overrideReasonDraft = ""
            return
        }

        guard state.phase == .locked else {
            return
        }

        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            return
        }

        guard overrideCooldownEndsAt != nil else {
            isOverrideComposerVisible = false
            return
        }

        if overrideCooldownRemaining == 0 {
            isOverrideComposerVisible = true
        } else {
            isOverrideComposerVisible = false
        }
    }

    /// Writes the current settings to the store. Separate from call
    /// sites so future batching / coalescing can plug in here.
    func persistSettings() {
        settingsStore.save(settings)
        syncWidgetSharedState()
    }

    /// Reacts to `@Published settings` changes: rebuilds budget trackers
    /// on limit/weekday changes, replays the week's usage so counts
    /// don't jump, pushes to CloudKit, and toggles the MCP monitor/
    /// socket pair with the MCP master switch.
    func handleSettingsMutation(from oldValue: CurfewSettings) {
        let extensionConfigChanged = settings.resetWeekday != oldValue.resetWeekday
            || settings.extensionWeeklyLimit != oldValue.extensionWeeklyLimit
            || settings.extensionDurationMinutes != oldValue.extensionDurationMinutes
        if extensionConfigChanged {
            let usedExtensions = max(0, oldValue.extensionWeeklyLimit - extensionsRemaining)
            // Preserve the previous tracker's lastResetBoundary so a same-
            // week settings tweak (limit, duration, or reset weekday) does
            // not surprise-reset the budget on the next tick. Seeding nil
            // keeps the v0.1 behavior for first-launch construction.
            extensionTracker = ExtensionBudgetTracker(
                weeklyLimit: settings.extensionWeeklyLimit,
                extensionMinutes: settings.extensionDurationMinutes,
                resetWeekday: settings.resetWeekday,
                seedLastResetBoundary: extensionTracker.lastResetBoundary
            )
            if usedExtensions > 0 {
                for _ in 0 ..< usedExtensions where extensionTracker.remaining > 0 {
                    _ = extensionTracker.requestExtension(at: currentTime)
                }
            }
            extensionsRemaining = extensionTracker.remaining
        }

        let overrideConfigChanged = settings.resetWeekday != oldValue.resetWeekday
            || settings.overrideWeeklyLimit != oldValue.overrideWeeklyLimit
            || settings.overrideDurationMinutes != oldValue.overrideDurationMinutes
        if overrideConfigChanged {
            let usedOverrides = max(0, oldValue.overrideWeeklyLimit - overridesRemaining)
            overrideTracker = ExtensionBudgetTracker(
                weeklyLimit: settings.overrideWeeklyLimit,
                extensionMinutes: settings.overrideDurationMinutes,
                resetWeekday: settings.resetWeekday,
                seedLastResetBoundary: overrideTracker.lastResetBoundary
            )
            if usedOverrides > 0 {
                for _ in 0 ..< usedOverrides where overrideTracker.remaining > 0 {
                    _ = overrideTracker.requestExtension(at: currentTime)
                }
            }
            overridesRemaining = overrideTracker.remaining
        }

        persistSettings()
        cloudKitSyncEngine.push(settings)

        if settings.mcpEnabled != oldValue.mcpEnabled {
            if settings.mcpEnabled {
                mcpRequestMonitor.start()
                mcpSocketServer.start()
            } else {
                mcpRequestMonitor.stop()
                mcpSocketServer.stop()
            }
        }
    }

    /// Toggles the CGEventTap that intercepts ⌘⇥ / ⌘Q / ⌘⌥Esc during
    /// lockout. Called once per tick; tap lifecycle tracks the phase.
    func updateLockoutInterception(for phase: EnforcementPhase) {
        if phase == .locked {
            lockoutKeyInterceptor.start()
        } else {
            lockoutKeyInterceptor.stop()
        }
    }

    /// Advances `ShutdownWorkflow` and republishes the countdown line.
    /// `isActiveDevice = !isUserIdle` so idle Macs get the short grace.
    func updateShutdownWorkflow() {
        // Active-device test: during lockout the user is literally locked
        // out, so `!isUserIdle` is what actually matters — is the user
        // present at this Mac trying to save work? Fall through to
        // active=true when no DeviceRegistry context exists (single-
        // device builds) so behaviour stays the v0.1 default.
        let isActiveDevice = !isUserIdle
        shutdownWorkflow.update(
            now: currentTime,
            isLocked: state.phase == .locked,
            isEnabled: settings.autoShutdownEnabled && ShutdownSupport.isAvailable,
            delayMinutes: settings.autoShutdownDelayMinutes,
            controller: shutdownController,
            isActiveDevice: isActiveDevice
        )
        shutdownStatusLine = shutdownWorkflow.statusLine(now: currentTime)
    }

    /// `overrideReasonDraft` minus surrounding whitespace — used by the
    /// composer's character-count gate.
    var trimmedOverrideReason: String {
        overrideReasonDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort device name, stamped onto `OverrideEvent` writes so
    /// the Devices panel and retrospective can attribute overrides.
    func currentDeviceName() -> String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }
        if !ProcessInfo.processInfo.hostName.isEmpty {
            return ProcessInfo.processInfo.hostName
        }
        return "Unknown Device"
    }

    /// `YYYY-M-D` token used by the tick loop to detect calendar
    /// rollover without subscribing to `NSCalendar`'s notification.
    static func dayToken(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    /// Seeds `state` at app-model init — before `tick()` runs. Returns
    /// `.dayOff` pre-onboarding so a half-configured schedule never
    /// fires warnings on first launch.
    static func initialEvaluation(
        settings: CurfewSettings,
        now: Date,
        enforcementEngine: CurfewEnforcementEngine
    ) -> CurfewEvaluation {
        guard settings.hasCompletedInitialSetup else {
            return .dayOff
        }

        return enforcementEngine.evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )
    }

    /// Day-rollover bookkeeping: resets daily grant counters, the
    /// calendar-overlap dedup, the cross-device warning-stage set, runs
    /// the 52-week activity trim, and re-verifies the persisted Pro
    /// license so a tampered UserDefaults can't keep Pro alive forever.
    func handleDayRollover(to nextDayToken: String) {
        currentDayToken = nextDayToken
        extensionMinutesGrantedToday = 0
        snoozeMinutesGrantedToday = 0
        curfewOverlapPromptFiredForEventID = nil
        warningStagesFiredToday.removeAll()
        warningStagesFiredDayToken = nextDayToken
        activityRecorder.trim(
            olderThan: Self.activityRetentionSeconds,
            now: currentTime
        )
        licenseGate.reverifyStoredKey()
    }

    /// Active work minutes accumulated today; hours-based enforcement reads this.
    func workedMinutesToday(at now: Date) -> Int {
        WorkTimeAggregator.activeMinutesToday(
            now: now,
            events: activityRecorder.events(
                in: Calendar.current.startOfDay(for: now) ... now
            ),
            idleWindows: [],
            calendar: .current
        )
    }
}
