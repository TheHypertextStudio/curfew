import Foundation

/// Audit-log emitters for process-level facts: the respawn deterrent, app
/// launch and quit, and MCP consent verdicts, plus the domain-to-token
/// mapping the other two audit files share.
///
/// Split from `CurfewAppModel+Audit.swift` to stay inside the file-length
/// budget.
@MainActor
extension CurfewAppModel {
    // MARK: - Respawn guard

    /// Records the LaunchAgent respawn deterrent arming or failing to arm.
    /// A failure here is the difference between "quitting Curfew ends the
    /// lockout" and "it does not", so it belongs in the audit trail even
    /// though the app swallows the error and carries on.
    func recordAuditRespawnGuard(to state: String, failure: Error?) {
        var detail: [String: AuditValue] = [
            "phase": .string(AuditTokens.phase(self.state.phase))
        ]
        if let failure {
            detail["error"] = .string(failure.localizedDescription)
        }
        auditLog.emitIfChanged(
            key: "respawnGuard",
            to: state,
            event: .respawnGuardChanged,
            actor: .app,
            detail: detail,
            at: currentTime
        )
    }

    // MARK: - App lifecycle

    /// Records `app.launched` with the facts that decide whether this process
    /// can enforce anything at all.
    func recordAuditAppLaunched(enforcementArmed: Bool) {
        let info = Bundle.main.infoDictionary
        auditLog.emit(
            .appLaunched,
            actor: .app,
            detail: [
                "version": .string(info?["CFBundleShortVersionString"] as? String ?? "unknown"),
                "build": .string(info?["CFBundleVersion"] as? String ?? "unknown"),
                "flavor": .string(CurfewFlavor.current.rawValue),
                "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
                "enforcementArmed": .bool(enforcementArmed),
                "setupComplete": .bool(settings.hasCompletedInitialSetup),
                "accessibility": .string(AuditTokens.permission(isAccessibilityTrusted)),
                "autoShutdownEnabled": .bool(settings.autoShutdownEnabled),
                "scheduleDigest": .string(AuditScheduleSummary.digest(settings.schedule)),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
        // The launch record already states these, so the first tick should
        // not immediately restate them as transitions from nothing.
        auditLog.seed(key: "accessibility", value: AuditTokens.permission(isAccessibilityTrusted))
        auditLog.seed(key: "phase", value: AuditTokens.phase(state.phase))
    }

    /// Records a clean quit. The absence of this line before the next
    /// `app.launched` is itself the signal that the app was killed — which is
    /// the condition the privileged daemon acts on.
    func recordAuditAppTerminating() {
        auditLog.emit(
            .appTerminating,
            actor: .app,
            detail: [
                "phase": .string(AuditTokens.phase(state.phase)),
                "enforcementRunning": .bool(isEnforcementRunning)
            ],
            at: Date()
        )
    }

    // MARK: - MCP / CLI

    /// Records an inbound write request. The `detail` carries a digest of the
    /// arguments rather than the arguments themselves: the payload comes from
    /// an external process and can contain arbitrary text, so it is treated
    /// as untrusted content that must not be copied verbatim into a log line.
    func recordAuditMCPRequestReceived(_ request: MCPPendingRequest) {
        var detail = AuditRedaction.redactedDetail(request.argumentsJSON, prefix: "arguments")
        detail["requestId"] = .string(request.id.uuidString)
        detail["tool"] = .string(request.tool.rawValue)
        detail["signed"] = .bool(request.signature != nil)
        detail["signatureValid"] = .bool(MCPRequestSigner.verify(request))
        detail["policy"] = .string(aiConsentPolicy.rawValue)
        auditLog.emit(
            .mcpRequestReceived,
            actor: Self.auditActor(for: request),
            detail: detail,
            at: currentTime
        )
    }

    /// Records the consent outcome for a request. `denialReason` is
    /// app-authored copy, never user prose, so it is safe to write verbatim.
    func recordAuditMCPDecision(
        _ event: AuditEventType,
        request: MCPPendingRequest,
        actor: AuditActor,
        denialReason: String? = nil
    ) {
        var detail: [String: AuditValue] = [
            "requestId": .string(request.id.uuidString),
            "tool": .string(request.tool.rawValue),
            "policy": .string(aiConsentPolicy.rawValue)
        ]
        if let denialReason, !denialReason.isEmpty {
            detail["denialReason"] = .string(denialReason)
        }
        auditLog.emit(event, actor: actor, detail: detail, at: currentTime)
    }

    /// Best-effort origin for a queued request. `curfew-ctl` and `curfew-mcp`
    /// share the queue file and the envelope carries no client identifier
    /// today, so every entry is attributed to `mcp` without a client name.
    /// When `curfew-protocols` adds a client field this is the one place that
    /// changes.
    static func auditActor(for request: MCPPendingRequest) -> AuditActor {
        .mcp(client: nil)
    }

    // MARK: - Token mapping

    // Internal rather than `private`: Swift scopes `private` in an extension to
    // the file, and `CurfewAppModel+Audit.swift` needs these for the tick loop.

    static func auditShutdownToken(for phase: ShutdownWorkflow.Phase) -> String {
        switch phase {
        case .idle: "idle"
        case .scheduled: "scheduled"
        case .retryScheduled: "retry_scheduled"
        case .failed: "failed"
        case .permissionDenied: "permission_denied"
        case .completed: "completed"
        }
    }

    static func auditShutdownEvent(
        for phase: ShutdownWorkflow.Phase
    ) -> AuditEventType? {
        switch phase {
        case .idle: nil
        case .scheduled: .shutdownScheduled
        case .retryScheduled: .shutdownRetryScheduled
        case .failed: .shutdownFailed
        case .permissionDenied: .shutdownPermissionDenied
        case .completed: .shutdownExecuted
        }
    }

    static func auditShutdownFireDate(for phase: ShutdownWorkflow.Phase) -> Date? {
        switch phase {
        case .scheduled(let date), .retryScheduled(let date): date
        default: nil
        }
    }

    static func auditHealthToken(for health: EnforcementHealth) -> String {
        switch health {
        case .active: "active"
        case .degradedNoAccessibility: "degraded_no_accessibility"
        case .degradedTapDown: "degraded_tap_down"
        }
    }
}
