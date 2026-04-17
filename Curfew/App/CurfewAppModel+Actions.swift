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
    /// Activates Curfew and opens the standard Settings window.
    func openSettings() {
        appRouter.activate()
        appRouter.showSettings()
    }

    func showGettingStarted() {
        appRouter.activate()
        gettingStartedPresenter.present(model: self)
    }

    func dismissGettingStarted() {
        gettingStartedPresenter.dismiss()
    }

    func completeOnboardingFlow() {
        completeInitialSetup()
        dismissGettingStarted()
    }

    func completeInitialSetup() {
        guard !settings.hasCompletedInitialSetup else {
            return
        }
        settings.hasCompletedInitialSetup = true
        start()
    }

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

    func tapExtensionRequest() {}

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
        tick()
    }

    func requestNotificationSnooze() {
        guard state.warningStage.supportsSnooze else {
            return
        }
        snoozeMinutesGrantedToday += 1
        tick()
    }

    func beginOverrideRequest() {
        guard state.phase == .locked else {
            return
        }
        guard overridesRemaining > 0 else {
            isOverrideComposerVisible = false
            return
        }
        if overrideCooldownEndsAt == nil {
            overrideCooldownEndsAt = OverrideRequestPolicy.cooldownEnd(startedAt: currentTime)
        }
        if overrideCooldownRemaining == 0 {
            isOverrideComposerVisible = true
        }
    }

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
        overrideCooldownEndsAt = nil
        isOverrideComposerVisible = false
        grantOverride(reason: reason)
    }

    // MARK: - MCP consent

    /// Invoked by `MCPRequestMonitor` when new pending requests arrive.
    /// Applies auto-approve or auto-deny based on `aiConsentPolicy`; queues
    /// the rest in `pendingMCPRequests` for the consent sheet.
    func handleNewMCPRequests(_ requests: [MCPPendingRequest]) {
        for request in requests {
            switch aiConsentPolicy {
            case .autoApprove:
                approveMCPRequest(request)
            case .deny:
                denyMCPRequest(request, reason: "AI consent policy set to deny all.")
            case .queue:
                if !pendingMCPRequests.contains(where: { $0.id == request.id }) {
                    pendingMCPRequests.append(request)
                }
            }
        }
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
            if overrideTracker.requestExtension(at: currentTime) {
                grantOverride(reason: "[AI] \(decodedReason(from: request.argumentsJSON))")
            }
        }
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
        tick()
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
