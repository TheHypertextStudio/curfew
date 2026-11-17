import CurfewKit
import Foundation

enum ScheduleActivationOutcome: Equatable {
    case activated
    case requiresImmediateLockConfirmation
    case unavailable
}

/// User-facing actions on `CurfewAppModel`.
///
/// "Actions" means: methods invoked from UI event handlers (button taps,
/// menu selections, confirmations). Each one is designed to be idempotent
/// or otherwise safe to call repeatedly — UI surfaces should not have to
/// guard against double-firing, accidental re-entry, etc. The model owns
/// the state validity rules; callers just forward intent.
///
/// Keeping these methods in an extension (rather than the main class) means
/// the main `CurfewAppModel.swift` stays focused on state + lifecycle, and
/// someone reading the code can find all user-reachable actions in one file.
@MainActor
extension CurfewAppModel {
    /// Stable `WindowGroup` id for the first-launch Getting Started scene,
    /// shared by `CurfewApp` and the `openWindow`/`dismissWindow` triggers.
    static let gettingStartedWindowID = "getting-started"

    /// How the app responds to AI write requests. Backed by
    /// `settings.aiConsentPolicyRawValue` (the single source of truth) so it
    /// persists via the normal `settings.didSet → persistSettings` path.
    var aiConsentPolicy: AIConsentPolicy {
        get { AIConsentPolicy(rawValue: settings.aiConsentPolicyRawValue) ?? .queue }
        set { settings.aiConsentPolicyRawValue = newValue.rawValue }
    }

    /// Activates Curfew and opens the standard Settings window.
    func openSettings() {
        appRouter.activate()
        appRouter.showSettings()
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        if AccountOAuthCallbackRouter.shared.route(url) {
            return true
        }
        return handleLicenseActivationURL(url)
    }

    @discardableResult
    func handleLicenseActivationURL(_ url: URL) -> Bool {
        guard licenseActivation.open(url) else { return false }
        settingsDestination = .about
        openSettings()
        return true
    }

    /// Brings setup forward, retaining requests made before any window exists.
    func showGettingStarted() {
        appRouter.activate()
        appRouter.openWindow(id: Self.gettingStartedWindowID)
    }

    /// Dismisses setup through an available scene, including setup itself.
    func dismissGettingStarted() {
        appRouter.dismissWindow(id: Self.gettingStartedWindowID)
    }

    /// Marks initial setup complete and dismisses the Getting Started window.
    /// Idempotent — safe to call if setup was already completed.
    @discardableResult
    func completeOnboardingFlow(
        choice: AutomaticScheduleChoice,
        confirmedImmediateLock: Bool = false,
        at now: Date = Date()
    ) -> ScheduleActivationOutcome {
        let outcome = completeInitialSetup(
            choice: choice,
            confirmedImmediateLock: confirmedImmediateLock,
            at: now
        )
        if outcome == .activated {
            dismissGettingStarted()
        }
        return outcome
    }

    /// Flips `hasCompletedInitialSetup` to `true` and starts the enforcement
    /// tick loop. No-ops if setup was already completed.
    ///
    /// This is the single choke point for arming enforcement for the first
    /// time — it's called both from the Getting Started flow's "Finish Setup"
    /// and from shortcut buttons elsewhere (Today's empty-state CTA, Settings'
    /// "Complete Setup") that skip that flow entirely. Without Accessibility
    /// trust the keyboard shield can't do anything, so enforcement would arm
    /// silently inert; the guard below re-checks the *real* grant (not a
    /// self-attested checkbox) regardless of which surface called this, and
    /// prompts for it instead of completing setup on a broken foundation.
    @discardableResult
    func completeInitialSetup(
        choice: AutomaticScheduleChoice,
        confirmedImmediateLock: Bool = false,
        at now: Date = Date()
    ) -> ScheduleActivationOutcome {
        guard !settings.hasCompletedInitialSetup else {
            return .unavailable
        }
        guard isAccessibilityTrusted else {
            requestAccessibilityAccess()
            return .unavailable
        }
        let enabled = choice == .weeklySchedule
        if enabled, schedulePersistenceError != nil {
            return .unavailable
        }
        if enabled, scheduleMayLockOnArming(at: now), !confirmedImmediateLock {
            return .requiresImmediateLockConfirmation
        }
        settingsStore.saveAutomaticScheduleConsent(enabled)
        hasExplicitAutomaticScheduleConsent = true
        automaticScheduleEnabled = enabled
        settings.hasCompletedInitialSetup = true
        start()
        return .activated
    }

    /// Explicitly opts an already-onboarded remote-only install into its
    /// configured weekly schedule. The UI presents the effective schedule and
    /// immediate-lock warning before calling this action.
    @discardableResult
    func enableAutomaticSchedule(
        confirmedImmediateLock: Bool = false,
        at now: Date = Date()
    ) -> ScheduleActivationOutcome {
        guard settings.hasCompletedInitialSetup, !automaticScheduleEnabled,
              schedulePersistenceError == nil,
              settings.pendingScheduleChange == nil else { return .unavailable }
        guard isAccessibilityTrusted else {
            requestAccessibilityAccess()
            return .unavailable
        }
        if scheduleMayLockOnArming(at: now), !confirmedImmediateLock {
            return .requiresImmediateLockConfirmation
        }
        settingsStore.saveAutomaticScheduleConsent(true)
        hasExplicitAutomaticScheduleConsent = true
        automaticScheduleEnabled = true
        if started {
            tick()
        } else {
            start()
        }
        return .activated
    }

    /// Queues a schedule change to the built-in `preset`. Subject to the same
    /// anti-bypass cooldown as any other schedule change.
    func applyPreset(_ preset: SchedulePreset) {
        switch preset {
        case .nineToFive:
            queueScheduleUpdate(.standardNineToFive)
        case .startupHours:
            queueScheduleUpdate(.startupHours)
        case .halfDay:
            queueScheduleUpdate(.halfDay)
        }
    }

    /// Applies `update` to the rule for `day` and queues the resulting
    /// schedule change. Used by the per-day row editors in the schedule grid.
    func updateRule(for day: Weekday, update: (inout DayRule) -> Void) {
        var nextSchedule = editableSchedule
        var rule = nextSchedule.rule(for: day)
        update(&rule)
        nextSchedule.rules[day] = rule
        queueScheduleUpdate(nextSchedule)
    }

    /// Copies `lockMinutes` and `unlockMinutes` to every day, preserving each
    /// day's `isDayOff` flag so users don't accidentally re-enable rest days.
    func applyTimesToAllDays(lockMinutes: Int, unlockMinutes: Int) {
        var nextSchedule = editableSchedule
        for weekday in Weekday.allCases {
            var rule = nextSchedule.rule(for: weekday)
            rule.lockMinutes = lockMinutes
            rule.unlockMinutes = unlockMinutes
            nextSchedule.rules[weekday] = rule
        }
        queueScheduleUpdate(nextSchedule)
    }

    /// Consumes one extension slot, adds the configured duration to today's
    /// grant total, records the activity event, and re-ticks. No-ops when
    /// `canRequestExtension` is false or the budget is exhausted.
    func confirmExtensionRequest() {
        guard state.canRequestExtension else {
            recordAuditExtensionDenied(reason: "not_offered", actor: .user)
            return
        }
        guard grantPersistentExtension() else {
            extensionsRemaining = extensionTracker.remaining
            recordAuditExtensionDenied(reason: "budget_exhausted", actor: .user)
            return
        }

        activityRecorder.recordExtensionGranted(
            minutes: settings.extensionDurationMinutes,
            at: currentTime
        )
        recordAuditExtensionGranted(
            minutes: settings.extensionDurationMinutes,
            actor: .user
        )
        refreshAfterUserAction()
    }

    /// Whether Call it a day can begin the lock now: Curfew is on, the working
    /// window is open with a future curfew and a known unlock, and no override
    /// is holding the lock open.
    var canCallItADay: Bool {
        CallItADayGate.isAvailable(CallItADayGate.Situation(
            enforcing: isEnforcementRunning,
            setupComplete: settings.hasCompletedInitialSetup,
            phase: state.phase,
            now: currentTime,
            lockDate: state.lockDate,
            unlockDate: state.unlockDate,
            overrideActive: activeOverrideUntil != nil
        ))
    }

    /// Ends the working day now. Records that the person called it a day, then
    /// begins tonight's lock through the same durable path a scheduled lock
    /// uses: a ``LockoutDeadlineRecord`` that holds until the scheduled unlock,
    /// armed with the Curfew helper and enforced by the tick even across a
    /// relaunch. The lock transition raises the evening close-out as usual.
    /// Returns `false`, changing nothing, when it is not available.
    @discardableResult
    func callItADay() -> Bool {
        guard canCallItADay, let unlock = state.unlockDate else { return false }
        if let existing = lockoutDeadlineStore.load(), currentTime < existing.scheduledUnlockAt {
            return false
        }
        recordCalledItADay()
        let record: LockoutDeadlineRecord = if settings.accountSync.usesWakeCampaign {
            WakeLockoutDeadlineResolver.record(
                lockoutStartedAt: currentTime,
                scheduleUnlockAt: unlock,
                account: settings.accountSync,
                wakeStatus: accountWakeLedger.current
            )
        } else {
            LockoutDeadlineRecord(
                lockoutStartedAt: currentTime,
                scheduledUnlockAt: unlock,
                kind: state.trigger == .hours ? .scheduledHours : .scheduledTime
            )
        }
        lockoutDeadlineStore.save(record)
        if featureFlags.privilegedHelperEnabled {
            lastPrivilegedHeartbeatAt = currentTime
            Task { await privilegedHelperManager.armLockout(record) }
        }
        refreshAfterUserAction()
        return true
    }

    /// Grants a 1-minute snooze by adding to `snoozeMinutesGrantedToday`.
    /// Only effective during stages that `supportsSnooze` (T-30, T-15).
    func requestNotificationSnooze() {
        guard state.warningStage.supportsSnooze, grantPersistentSnooze() else { return }
        refreshAfterUserAction()
    }

    /// Shows the override composer. No-ops if the device is not locked or the
    /// weekly override budget is exhausted.
    func beginOverrideRequest() {
        guard state.phase == .locked else {
            recordAuditOverrideDenied(reason: "not_locked", actor: .user)
            return
        }
        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            recordAuditOverrideDenied(reason: "budget_exhausted", actor: .user)
            return
        }
        if overrideRequestedAt == nil {
            overrideRequestedAt = currentTime
        }
        isOverrideComposerVisible = true
    }

    /// Validates `canConfirmOverride`, consumes one override slot, clears
    /// the composer, and calls `grantOverride(reason:)`. No-ops on any failed
    /// gate check.
    func confirmOverride() {
        guard canConfirmOverride else {
            recordAuditOverrideDenied(reason: "gate_failed", actor: .user)
            return
        }
        recordAuditOverrideRequested(reason: trimmedOverrideReason)
        guard grantPersistentOverride() else {
            recordAuditOverrideDenied(reason: "budget_exhausted", actor: .user)
            return
        }
        let reason = trimmedOverrideReason
        overrideReasonDraft = ""
        isOverrideComposerVisible = false
        overrideRequestedAt = nil
        grantOverride(reason: reason)
    }

    private func grantOverride(reason: String) {
        lockoutMessage = voice.released
        let event = OverrideEvent(
            timestamp: currentTime,
            deviceName: currentDeviceName(),
            reason: reason,
            grantedDurationMinutes: settings.overrideDurationMinutes
        )
        recordOverrideEvent(event)
        refreshAfterUserAction()
    }

    /// Persists the given override event to the store, appends it to the
    /// published in-memory log via ``appendOverrideEvent(_:)``, and records it
    /// to the activity log. The append hop is a thin main-class mutator because
    /// `overrideEvents` is `@Published private(set)`.
    ///
    /// - Parameter event: The granted override to persist and record.
    func recordOverrideEvent(_ event: OverrideEvent) {
        settingsStore.appendOverrideEvent(event)
        appendOverrideEvent(event)
        activityRecorder.recordOverrideGranted(
            minutes: event.grantedDurationMinutes,
            reason: event.reason,
            at: event.timestamp
        )
        recordAuditOverrideGranted(event: event)
    }

    private func decodedReason(from argumentsJSON: String) -> String {
        guard
            let data = argumentsJSON.data(using: .utf8),
            let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let reason = args["reason"] as? String
        else {
            return "(no reason provided)"
        }
        return reason
    }
}

/// When Call it a day may begin the lock. Pure, so the gating is tested
/// without a model.
enum CallItADayGate {
    struct Situation: Equatable {
        var enforcing: Bool
        var setupComplete: Bool
        var phase: EnforcementPhase
        var now: Date
        var lockDate: Date?
        var unlockDate: Date?
        var overrideActive: Bool
    }

    static func isAvailable(_ situation: Situation) -> Bool {
        guard situation.enforcing, situation.setupComplete,
              situation.phase == .working || situation.phase == .warning,
              !situation.overrideActive,
              let lock = situation.lockDate, lock > situation.now,
              let unlock = situation.unlockDate, unlock > lock, unlock != .distantFuture
        else { return false }
        return true
    }
}
