import CurfewKit
import Foundation
import OSLog

/// MCP consent handling — routing new requests through the AI consent
/// policy, applying an approved request's effect, and persisting the
/// approve/deny decision back to the queue file. Split out of `+Actions`
/// so this self-contained concern doesn't crowd the general action list.
@MainActor
extension CurfewAppModel {
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
    ///
    /// The status written reflects whether the action actually took effect —
    /// e.g. the user approves an extension request, but the budget was
    /// exhausted or the phase moved on in the window between queueing and
    /// approval, so `applyMCPAction` no-ops. Previously this still wrote
    /// `.approved` unconditionally, so both the consent sheet and
    /// `curfew-mcp`'s caller reported success for something that silently
    /// did nothing.
    func approveMCPRequest(_ request: MCPPendingRequest) {
        let applied = applyMCPAction(request)
        var updated = request
        if applied {
            updated.status = .approved
        } else {
            updated.status = .denied
            updated.denialReason = "Approved, but no longer eligible when applied."
        }
        updated.resolvedAt = Date()
        writeMCPQueueUpdate(updated)
        pendingMCPRequests.removeAll { $0.id == request.id }
    }

    /// Denies the given MCP request and updates the queue file so
    /// `curfew-mcp` returns a refusal to the client.
    func denyMCPRequest(_ request: MCPPendingRequest, reason: String = "") {
        var updated = request
        updated.status = .denied
        updated.resolvedAt = Date()
        updated.denialReason = reason.isEmpty ? nil : reason
        writeMCPQueueUpdate(updated)
        pendingMCPRequests.removeAll { $0.id == request.id }
    }

    /// Persists an approve/deny decision to the queue file, logging (rather
    /// than silently discarding) a write failure. The sheet still dequeues
    /// the request either way: the action side-effect (e.g. an extension
    /// grant) already happened by this point, so re-presenting the same
    /// request would risk the user re-approving it and double-firing that
    /// side-effect. A failed write instead leaves `curfew-mcp` waiting on a
    /// stale `.pending` entry until its own timeout — worse than a stuck
    /// sheet, but not silently invisible the way a bare `try?` was.
    private func writeMCPQueueUpdate(_ request: MCPPendingRequest) {
        do {
            try MCPRequestQueue.update(request)
        } catch {
            let logger = Logger(subsystem: "studio.hypertext.curfew", category: "mcp-queue")
            logger.error(
                "failed to persist MCP decision for \(request.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Private MCP helpers

    /// Applies `request`'s effect and reports whether it actually took hold,
    /// so ``approveMCPRequest(_:)`` can record the true outcome rather than
    /// unconditionally claiming success.
    private func applyMCPAction(_ request: MCPPendingRequest) -> Bool {
        switch request.tool {
        case .requestExtension:
            // Grant an extension if the budget allows and we're in warning phase.
            guard state.canRequestExtension else { return false }
            _ = extensionTracker.requestExtension(at: currentTime)
            extensionMinutesGrantedToday += settings.extensionDurationMinutes
            extensionsRemaining = extensionTracker.remaining
            activityRecorder.recordExtensionGranted(
                minutes: settings.extensionDurationMinutes,
                at: currentTime
            )
            tick()
            return true
        case .requestOverride:
            // Override grants are user-only. The friction model — 5-minute
            // cooldown, 50-character reason, 3-second hold — is the
            // structural defense against impulsive overrides; routing any
            // of that through a remote channel undermines the contract.
            // Legacy queue entries that still reach this case are denied
            // upstream in `handleNewMCPRequests`; this branch is a guard
            // against a queue file racing in mid-removal.
            return false
        case .setSchedule:
            return applyMCPScheduleUpdate(request)
        }
    }

    /// Parses a queued `.setSchedule` request and routes it through the same
    /// `queueScheduleUpdate` path the in-app editor uses, so `SchedulePolicyEngine`
    /// applies anti-bypass classification (strictly better = next day;
    /// weaker = 24 h cooldown). Malformed payloads no-op rather than throw —
    /// the tool-side validator already rejected the common failures before
    /// the request was queued.
    private func applyMCPScheduleUpdate(_ request: MCPPendingRequest) -> Bool {
        guard
            let data = request.argumentsJSON.data(using: .utf8),
            let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let weekdayName = args["weekday"] as? String,
            let weekday = mcpWeekday(from: weekdayName),
            let lockTime = args["lock_time"] as? String,
            let lockMinutes = parseHHMMMinutes(lockTime)
        else {
            return false
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
        return true
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
}
