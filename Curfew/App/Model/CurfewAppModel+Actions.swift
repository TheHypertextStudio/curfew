import CurfewKit
import Foundation

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

    /// Brings the app to the foreground and requests the Getting Started window.
    /// Bumps ``gettingStartedRequestID``; the SwiftUI scene graph observes it
    /// and opens the `WindowGroup(id: "getting-started")` via `openWindow`.
    func showGettingStarted() {
        appRouter.activate()
        gettingStartedRequestID += 1
    }

    /// Requests dismissal of the Getting Started window by bumping
    /// ``gettingStartedDismissID``; the scene graph observes it and calls
    /// `dismissWindow`.
    func dismissGettingStarted() {
        gettingStartedDismissID += 1
    }

    /// Marks initial setup complete and dismisses the Getting Started window.
    /// Idempotent — safe to call if setup was already completed.
    func completeOnboardingFlow() {
        completeInitialSetup()
        dismissGettingStarted()
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
    func completeInitialSetup() {
        guard !settings.hasCompletedInitialSetup else {
            return
        }
        guard isAccessibilityTrusted else {
            requestAccessibilityAccess()
            return
        }
        settings.hasCompletedInitialSetup = true
        start()
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

    /// Placeholder called when the user taps (not holds) the extension button.
    /// No-ops currently; reserved for future haptic / visual tap feedback.
    func tapExtensionRequest() {}

    /// Consumes one extension slot, adds the configured duration to today's
    /// grant total, records the activity event, and re-ticks. No-ops when
    /// `canRequestExtension` is false or the budget is exhausted.
    func confirmExtensionRequest() {
        guard state.canRequestExtension else {
            return
        }
        guard extensionTracker.requestExtension(at: currentTime) else {
            extensionsRemaining = extensionTracker.remaining
            return
        }

        extensionsRemaining = extensionTracker.remaining
        extensionMinutesGrantedToday += settings.extensionDurationMinutes
        activityRecorder.recordExtensionGranted(
            minutes: settings.extensionDurationMinutes,
            at: currentTime
        )
        refreshAfterUserAction()
    }

    /// Grants a 1-minute snooze by adding to `snoozeMinutesGrantedToday`.
    /// Only effective during stages that `supportsSnooze` (T-30, T-15).
    func requestNotificationSnooze() {
        guard state.warningStage.supportsSnooze else {
            return
        }
        snoozeMinutesGrantedToday += 1
        refreshAfterUserAction()
    }

    /// Shows the override composer. No-ops if the device is not locked or the
    /// weekly override budget is exhausted.
    func beginOverrideRequest() {
        guard state.phase == .locked else {
            return
        }
        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            return
        }
        isOverrideComposerVisible = true
    }

    /// Validates `canConfirmOverride`, consumes one override slot, clears
    /// the composer, and calls `grantOverride(reason:)`. No-ops on any failed
    /// gate check.
    func confirmOverride() {
        guard canConfirmOverride else {
            return
        }
        guard overrideTracker.requestExtension(at: currentTime) else {
            overridesRemaining = overrideTracker.remaining
            return
        }
        let reason = trimmedOverrideReason
        overrideReasonDraft = ""
        isOverrideComposerVisible = false
        grantOverride(reason: reason)
    }

    private func grantOverride(reason: String) {
        overrideUntil = currentTime
            .addingTimeInterval(TimeInterval(settings.overrideDurationMinutes * 60))
        overridesRemaining = overrideTracker.remaining
        lockoutMessage = EncouragementMessageCatalog.postOverride
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
