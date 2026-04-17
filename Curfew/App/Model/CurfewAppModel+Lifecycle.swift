import Combine
import EventKit
import Foundation
import UserNotifications
import WidgetKit

/// Engine-side internals of `CurfewAppModel` — the tick loop plus all
/// private helpers that translate engine output into published state.
///
/// Nothing in this file is called directly from UI code; everything here is
/// either driven by the tick timer or is reacting to a user action that
/// originated in `CurfewAppModel+Actions`. Kept separate from actions and
/// presentation so a reader investigating "why does the lockout fire early?"
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
    /// 7. Propagate derived effects: rotate lockout message on entry, update
    ///    override composer visibility, fire/cancel warning notifications,
    ///    install/uninstall key tap, advance shutdown workflow, redraw
    ///    overlays.
    func tick() {
        let previousPhase = state.phase
        currentTime = Date()

        // Idle sampling lives at the top of the tick so downstream surfaces
        // (and any consumers observing `isUserIdle`) see today's true state
        // before the engine runs. `sample()` fires `onIdleStateChanged`
        // only on transitions, so 1 Hz polling costs one CGEventSource read.
        idleWatcher.sample()

        if Self.dayToken(for: currentTime) != currentDayToken {
            currentDayToken = Self.dayToken(for: currentTime)
            extensionMinutesGrantedToday = 0
            snoozeMinutesGrantedToday = 0
            curfewOverlapPromptFiredForEventID = nil
            // Enforces the 52-week retention promise in PRIVACY.md. Called
            // on day rollover so the work happens at most once per day and
            // never during a warning-phase tick where allocation jitter
            // might be user-visible.
            activityRecorder.trim(
                olderThan: Self.activityRetentionSeconds,
                now: currentTime
            )
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

        propagatePhaseTransition(from: previousPhase)

        activityRecorder.recordPhaseTransition(
            from: previousPhase,
            to: state.phase,
            at: currentTime
        )
        reconcileOverrideComposerState(previousPhase: previousPhase)
        notificationManager.update(stage: state.warningStage, now: currentTime)
        updateLockoutInterception(for: state.phase)
        updateShutdownWorkflow()
        overlayCoordinator.updateOverlays(for: state, model: self, lockoutMessage: lockoutMessage)
        checkCalendarCurfewOverlap()
    }

    private func propagatePhaseTransition(from previousPhase: EnforcementPhase) {
        if previousPhase != .locked, state.phase == .locked {
            lockoutMessage = EncouragementMessageCatalog.next(after: lockoutMessage)
        }
        // Reload widget timelines on both phase transitions and warning-
        // stage transitions. The old behaviour only covered phase, so a
        // widget viewed during warning escalation stayed on stale copy
        // until the lockout moment. Per-stage reloads keep the ring and
        // the label in sync with what the app thinks is happening.
        if featureFlags.widgetKitEnabled,
           previousPhase != state.phase || previousWarningStage != state.warningStage {
            WidgetCenter.shared.reloadTimelines(ofKind: "CurfewWidget")
        }
        previousWarningStage = state.warningStage
        if previousPhase != state.phase, featureFlags.privilegedHelperEnabled {
            if state.phase == .locked {
                LockoutStatePersistence.markLockoutActive()
            } else if previousPhase == .locked {
                LockoutStatePersistence.markLockoutInactive()
            }
        }
    }

    /// Fires a UNUserNotification once per event when a calendar event is
    /// starting within 60 minutes of the user's curfew gate and the app is in
    /// the working or warning phase. The user can act on the notification to
    /// request an extension from the popover. Silently no-ops when:
    ///   - Calendar feature flag is off or Pro is not unlocked.
    ///   - No event is in the overlap window.
    ///   - We've already prompted for this event today.
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

    func queueScheduleUpdate(_ proposedSchedule: WeeklySchedule) {
        let classification = policyEngine.classifyChange(
            from: settings.schedule,
            to: proposedSchedule
        )
        if classification == .noChange {
            settings.pendingScheduleChange = nil
            persistSettings()
            tick()
            return
        }

        let effectiveDate = policyEngine.earliestEffectiveDate(
            for: classification,
            requestedAt: currentTime
        )
        settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: proposedSchedule,
            requestedAt: currentTime,
            effectiveAt: effectiveDate,
            classification: classification
        )
        persistSettings()
        tick()
    }

    func applyPendingScheduleIfNeeded(now: Date) {
        guard let pending = settings.pendingScheduleChange else {
            return
        }
        guard now >= pending.effectiveAt else {
            return
        }
        settings.schedule = pending.proposedSchedule
        settings.pendingScheduleChange = nil
        persistSettings()
    }

    func persistSettings() {
        settingsStore.save(settings)
    }

    func handleSettingsMutation(from oldValue: CurfewSettings) {
        let extensionConfigChanged = settings.resetWeekday != oldValue.resetWeekday
            || settings.extensionWeeklyLimit != oldValue.extensionWeeklyLimit
            || settings.extensionDurationMinutes != oldValue.extensionDurationMinutes
        if extensionConfigChanged {
            let usedExtensions = max(0, oldValue.extensionWeeklyLimit - extensionsRemaining)
            extensionTracker = ExtensionBudgetTracker(
                weeklyLimit: settings.extensionWeeklyLimit,
                extensionMinutes: settings.extensionDurationMinutes,
                resetWeekday: settings.resetWeekday
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
                resetWeekday: settings.resetWeekday
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
            } else {
                mcpRequestMonitor.stop()
            }
        }
    }

    func updateLockoutInterception(for phase: EnforcementPhase) {
        if phase == .locked {
            lockoutKeyInterceptor.start()
        } else {
            lockoutKeyInterceptor.stop()
        }
    }

    func updateShutdownWorkflow() {
        shutdownWorkflow.update(
            now: currentTime,
            isLocked: state.phase == .locked,
            isEnabled: settings.autoShutdownEnabled,
            delayMinutes: settings.autoShutdownDelayMinutes,
            controller: shutdownController
        )
        shutdownStatusLine = shutdownWorkflow.statusLine(now: currentTime)
    }

    var trimmedOverrideReason: String {
        overrideReasonDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentDeviceName() -> String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }
        if !ProcessInfo.processInfo.hostName.isEmpty {
            return ProcessInfo.processInfo.hostName
        }
        return "Unknown Device"
    }

    static func dayToken(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

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

    /// Active work minutes accumulated today; hours-based enforcement
    /// reads this. Kept out of `tick()` so the tick body stays tight.
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

    /// Subscribes to license activation/deactivation so Pro engines start
    /// or stop without requiring an app relaunch. Debounces via the main
    /// run loop so the didSet cascade settles before engines bounce.
    func subscribeToLicenseChanges() {
        licenseGate.$activatedKey
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileProGatedModules()
            }
            .store(in: &cancellables)
    }

    /// Starts or stops CloudKit, Calendar, and the privileged helper based
    /// on the current `FeatureFlags` + `LicenseGate` combination. Idempotent:
    /// `cloudKitSyncEngine.start()` guards on `!active`, and the calendar /
    /// helper start calls no-op when already configured.
    func reconcileProGatedModules() {
        let pro = licenseGate.isProUnlocked

        if featureFlags.cloudSyncEnabled, pro {
            cloudKitSyncEngine.start(
                localSettings: settings,
                localModifiedAt: Date()
            )
            deviceRegistry.start()
        } else {
            cloudKitSyncEngine.stop()
            deviceRegistry.stop()
        }

        if featureFlags.calendarEnabled, pro {
            calendarMonitor.requestAccessAndSync()
        } else {
            calendarMonitor.stop()
        }

        if featureFlags.privilegedHelperEnabled {
            privilegedHelperManager.refreshStatus()
        }
    }
}
