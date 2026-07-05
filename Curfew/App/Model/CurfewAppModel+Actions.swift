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
    func completeInitialSetup() {
        guard !settings.hasCompletedInitialSetup else {
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

    // MARK: - MCP consent

    /// Invoked by `MCPRequestMonitor` when new pending requests arrive.
    /// Applies auto-approve or auto-deny based on `aiConsentPolicy`; queues
    /// the rest in `pendingMCPRequests` for the consent sheet.
    ///
    /// Override requests are always denied regardless of policy — the
    /// friction model (cooldown + reason + hold) is the structural defence
    /// against impulsive overrides and applies only in-app. The MCP tool
    /// surface no longer advertises `request_override`; this guard catches
    /// legacy entries left in the queue file from older builds.
    ///
    /// Unsigned or signature-invalid requests are routed to the consent
    /// sheet even under `.autoApprove`, closing the bypass surface where a
    /// rogue user-process could append a forged request and have the app
    /// approve it silently.
    func handleNewMCPRequests(_ requests: [MCPPendingRequest]) {
        for request in requests {
            if request.tool == .requestOverride {
                denyMCPRequest(
                    request,
                    reason: "Override grants are user-only — confirm one in-app."
                )
                continue
            }
            let policy = effectiveConsentPolicy(for: request)
            switch policy {
            case .autoApprove:
                approveMCPRequest(request)
            case .deny:
                denyMCPRequest(request, reason: "Consent policy set to deny all.")
            case .queue:
                if !pendingMCPRequests.contains(where: { $0.id == request.id }) {
                    pendingMCPRequests.append(request)
                }
            }
        }
    }

    /// Returns the effective policy for `request` after applying signature
    /// verification: a missing or invalid signature downgrades
    /// `.autoApprove` to `.queue` so the consent sheet always shows for
    /// requests we can't authenticate. Signed-and-valid requests honor
    /// the user's configured policy unchanged.
    private func effectiveConsentPolicy(for request: MCPPendingRequest) -> AIConsentPolicy {
        guard aiConsentPolicy == .autoApprove else {
            return aiConsentPolicy
        }
        return MCPRequestSigner.verify(request) ? .autoApprove : .queue
    }

    /// Approves the given MCP request, applies the action, and updates the
    /// queue file so `curfew-mcp` can return success to the client.
    func approveMCPRequest(_ request: MCPPendingRequest) {
        applyMCPAction(request)
        var updated = request
        updated.status = .approved
        updated.resolvedAt = Date()
        try? MCPRequestQueue.update(updated)
        pendingMCPRequests.removeAll { $0.id == request.id }
    }

    /// Denies the given MCP request and updates the queue file so
    /// `curfew-mcp` returns a refusal to the client.
    func denyMCPRequest(_ request: MCPPendingRequest, reason: String = "") {
        var updated = request
        updated.status = .denied
        updated.resolvedAt = Date()
        updated.denialReason = reason.isEmpty ? nil : reason
        try? MCPRequestQueue.update(updated)
        pendingMCPRequests.removeAll { $0.id == request.id }
    }

    // MARK: - Private MCP helpers

    private func applyMCPAction(_ request: MCPPendingRequest) {
        switch request.tool {
        case .requestExtension:
            // Grant an extension if the budget allows and we're in warning phase.
            if state.canRequestExtension {
                _ = extensionTracker.requestExtension(at: currentTime)
                extensionMinutesGrantedToday += settings.extensionDurationMinutes
                extensionsRemaining = extensionTracker.remaining
                activityRecorder.recordExtensionGranted(
                    minutes: settings.extensionDurationMinutes,
                    at: currentTime
                )
                tick()
            }
        case .requestOverride:
            // Override grants are user-only. The friction model — 5-minute
            // cooldown, 50-character reason, 3-second hold — is the
            // structural defense against impulsive overrides; routing any
            // of that through a remote channel undermines the contract.
            // Legacy queue entries that still reach this case are denied
            // upstream in `handleNewMCPRequests`; this branch is a guard
            // against a queue file racing in mid-removal.
            break
        case .setSchedule:
            applyMCPScheduleUpdate(request)
        }
    }

    /// Parses a queued `.setSchedule` request and routes it through the same
    /// `queueScheduleUpdate` path the in-app editor uses, so `SchedulePolicyEngine`
    /// applies anti-bypass classification (strictly better = next day;
    /// weaker = 24 h cooldown). Malformed payloads no-op rather than throw —
    /// the tool-side validator already rejected the common failures before
    /// the request was queued.
    private func applyMCPScheduleUpdate(_ request: MCPPendingRequest) {
        guard
            let data = request.argumentsJSON.data(using: .utf8),
            let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let weekdayName = args["weekday"] as? String,
            let weekday = mcpWeekday(from: weekdayName),
            let lockTime = args["lock_time"] as? String,
            let lockMinutes = parseHHMMMinutes(lockTime)
        else {
            return
        }

        let currentRule = settings.schedule.rule(for: weekday)
        let unlockMinutes: Int = if let unlockString = args["unlock_time"] as? String,
                                    let parsed = parseHHMMMinutes(unlockString) {
            parsed
        } else {
            currentRule.unlockMinutes
        }
        let isDayOff: Bool = if let flag = args["is_day_off"] as? Bool {
            flag
        } else if let flagString = args["is_day_off"] as? String {
            (flagString as NSString).boolValue
        } else {
            currentRule.isDayOff
        }

        var proposedRules = settings.schedule.rules
        proposedRules[weekday] = DayRule(
            isDayOff: isDayOff,
            lockMinutes: lockMinutes,
            unlockMinutes: unlockMinutes,
            exception: currentRule.exception
        )
        let proposed = WeeklySchedule(rules: proposedRules)
        queueScheduleUpdate(proposed)
    }

    /// Local version of the `weekdayFromName` helper that lives in the MCP
    /// tool file — the app target doesn't depend on the MCP server binary,
    /// so we keep a second copy here to avoid pulling the CLI target into
    /// the app module graph.
    private func mcpWeekday(from name: String) -> Weekday? {
        switch name.lowercased() {
        case "monday": .monday
        case "tuesday": .tuesday
        case "wednesday": .wednesday
        case "thursday": .thursday
        case "friday": .friday
        case "saturday": .saturday
        case "sunday": .sunday
        default: nil
        }
    }

    /// Parses "HH:MM" (24 h) to minutes-past-midnight.
    private func parseHHMMMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              hour >= 0, hour < 24, minute >= 0, minute < 60
        else {
            return nil
        }
        return hour * 60 + minute
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
