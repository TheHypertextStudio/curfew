import Foundation

/// Who resolved a queued MCP request.
///
/// Callers never name this type. It exists so that the one function which
/// resolves a request — updating the queue file and writing the audit record —
/// derives both the event and the actor from a single fact, instead of each
/// call site stating an actor it could state wrongly.
private enum MCPConsentSource {
    /// A person acted in the consent sheet.
    case person

    /// `aiConsentPolicy`, or the override guard, decided with no human
    /// involved.
    case policy

    var auditActor: AuditActor {
        switch self {
        case .person: .user
        case .policy: .app
        }
    }

    /// The event written when this source approves. Denials share one event
    /// and are distinguished by `actor` alone; approvals do not, because
    /// "a person approved this" and "nobody was asked" are different enough
    /// that an auditor should be able to grep them apart.
    var approvalEvent: AuditEventType {
        switch self {
        case .person: .mcpRequestApproved
        case .policy: .mcpRequestAutoApproved
        }
    }
}

/// Resolution of queued MCP write requests, and the audit record each
/// resolution produces.
///
/// Four entry points, split by *who decided* rather than by what happened:
/// ``approveMCPRequest(_:)`` and ``denyMCPRequest(_:reason:)`` are the consent
/// sheet's, and ``autoApproveMCPRequest(_:)`` and
/// ``denyMCPRequestByPolicy(_:reason:)`` are the policy engine's. The actor is
/// not a parameter anyone passes, so a UI handler cannot file its click as an
/// automatic decision and a policy branch cannot put a person's name on a
/// choice they never saw. Every one of them funnels into
/// ``resolveMCPRequest(_:approved:decidedBy:reason:)``, which is the only place
/// that writes the queue file or emits a consent record.
///
/// This shape exists because the first version took the shorter road — one
/// `approveMCPRequest` and one `denyMCPRequest`, each hardcoding `.user` —
/// and both were shared with policy-driven callers. The log then asserted,
/// with a timestamp and a hash, that a person had denied requests they were
/// never shown. A confident false attribution in an audit trail is worse than
/// no record at all, so the actor is now structural rather than stated.
@MainActor
extension CurfewAppModel {
    /// Approves a request the user accepted in the consent sheet.
    func approveMCPRequest(_ request: MCPPendingRequest) {
        resolveMCPRequest(request, approved: true, decidedBy: .person, reason: "")
    }

    /// Approves a request the consent policy accepted without asking anyone.
    func autoApproveMCPRequest(_ request: MCPPendingRequest) {
        resolveMCPRequest(request, approved: true, decidedBy: .policy, reason: "")
    }

    /// Denies a request the user rejected in the consent sheet.
    func denyMCPRequest(_ request: MCPPendingRequest, reason: String = "") {
        resolveMCPRequest(request, approved: false, decidedBy: .person, reason: reason)
    }

    /// Denies a request Curfew refused on its own — the deny-all policy, or
    /// the guard that keeps override grants out of the MCP surface entirely.
    func denyMCPRequestByPolicy(_ request: MCPPendingRequest, reason: String) {
        resolveMCPRequest(request, approved: false, decidedBy: .policy, reason: reason)
    }

    /// Records the decision, applies it, and updates the queue file so
    /// `curfew-mcp` can answer its client.
    ///
    /// The audit record is written before the action is applied: an approval
    /// that crashes halfway through applying still leaves evidence that it was
    /// approved, which is the direction an audit trail should fail in.
    private func resolveMCPRequest(
        _ request: MCPPendingRequest,
        approved: Bool,
        decidedBy source: MCPConsentSource,
        reason: String
    ) {
        recordAuditMCPDecision(
            approved ? source.approvalEvent : .mcpRequestDenied,
            request: request,
            actor: source.auditActor,
            denialReason: approved ? nil : reason
        )

        if approved {
            applyMCPAction(request)
        }

        var updated = request
        updated.status = approved ? .approved : .denied
        updated.resolvedAt = Date()
        updated.denialReason = approved || reason.isEmpty ? nil : reason
        try? MCPRequestQueue.update(updated)
        pendingMCPRequests.removeAll { $0.id == request.id }
    }
}
