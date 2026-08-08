import Foundation

/// Audit-log emitters for the paths a person or an assistant drives:
/// schedule mutations, extension grants, and override grants.
///
/// Split from `CurfewAppModel+Audit.swift` to stay inside the file-length
/// budget; that file owns the tick loop, lifecycle, and MCP consent records
/// and documents the rules both files follow.
@MainActor
extension CurfewAppModel {
    // MARK: - Schedule

    /// Records a submitted schedule change and how `SchedulePolicyEngine`
    /// classified it. `actor` names who asked — the person in Settings, an
    /// MCP client, or `curfew-ctl`.
    func recordAuditScheduleRequested(
        proposed: WeeklySchedule,
        classification: ScheduleChangeClassification,
        effectiveAt: Date?,
        actor: AuditActor
    ) {
        var detail: [String: AuditValue] = [
            "classification": .string(classification.rawValue),
            "changedDays": .string(
                AuditScheduleSummary.changedDays(from: settings.schedule, to: proposed)
            )
        ]
        if let effectiveAt {
            detail["effectiveAt"] = .string(AuditTimestamp.string(from: effectiveAt))
        }
        auditLog.emit(
            .scheduleChangeRequested,
            actor: actor,
            from: AuditScheduleSummary.digest(settings.schedule),
            to: AuditScheduleSummary.digest(proposed),
            detail: detail,
            at: currentTime
        )
    }

    /// Records a due change the apply path refused to install. Today the only
    /// reason is the anti-bypass rule that will not loosen a schedule while
    /// the user is locked out; the reason is a token so a new rule can be
    /// added without a new event type.
    ///
    /// Deduplicated by pending change: `applyPendingScheduleIfNeeded` re-runs
    /// the same refusal on every tick for as long as the lockout lasts, and
    /// the log wants one line per decision, not one per second.
    func recordAuditScheduleDeferred(
        pending: PendingScheduleChange,
        reason: String
    ) {
        let proposedDigest = AuditScheduleSummary.digest(pending.proposedSchedule)
        auditLog.emitIfChanged(
            key: "scheduleDeferred",
            to: "\(proposedDigest)/\(reason)",
            event: .scheduleChangeDeferred,
            actor: .app,
            detail: [
                "reason": .string(reason),
                "fromDigest": .string(AuditScheduleSummary.digest(settings.schedule)),
                "toDigest": .string(proposedDigest),
                "classification": .string(pending.classification.rawValue),
                "requestedAt": .string(AuditTimestamp.string(from: pending.requestedAt)),
                "effectiveAt": .string(AuditTimestamp.string(from: pending.effectiveAt))
            ],
            at: currentTime
        )
    }

    /// Records the user withdrawing a queued change by editing the schedule
    /// back to what it already is.
    func recordAuditScheduleCancelled(
        pending: PendingScheduleChange,
        actor: AuditActor
    ) {
        auditLog.emit(
            .scheduleChangeCancelled,
            actor: actor,
            from: AuditScheduleSummary.digest(pending.proposedSchedule),
            to: AuditScheduleSummary.digest(settings.schedule),
            detail: [
                "classification": .string(pending.classification.rawValue),
                "requestedAt": .string(AuditTimestamp.string(from: pending.requestedAt)),
                "effectiveAt": .string(AuditTimestamp.string(from: pending.effectiveAt))
            ],
            at: currentTime
        )
    }

    /// Records a pending change reaching its effective date and taking hold.
    func recordAuditScheduleApplied(pending: PendingScheduleChange) {
        auditLog.emit(
            .scheduleChangeApplied,
            actor: .app,
            from: AuditScheduleSummary.digest(settings.schedule),
            to: AuditScheduleSummary.digest(pending.proposedSchedule),
            detail: [
                "classification": .string(pending.classification.rawValue),
                "requestedAt": .string(AuditTimestamp.string(from: pending.requestedAt)),
                "effectiveAt": .string(AuditTimestamp.string(from: pending.effectiveAt)),
                "delaySeconds": .int(
                    Int(pending.effectiveAt.timeIntervalSince(pending.requestedAt))
                )
            ],
            at: currentTime
        )
    }

    // MARK: - Grants

    /// Records an extension grant with the budget it consumed.
    func recordAuditExtensionGranted(minutes: Int, actor: AuditActor) {
        auditLog.emit(
            .extensionGranted,
            actor: actor,
            detail: [
                "minutes": .int(minutes),
                "budgetRemaining": .int(extensionsRemaining),
                "budgetLimit": .int(settings.extensionWeeklyLimit),
                "minutesGrantedToday": .int(extensionMinutesGrantedToday),
                "warningStage": .string(AuditTokens.warningStage(state.warningStage))
            ],
            at: currentTime
        )
    }

    /// Records a refused extension. `reason` is a stable token
    /// (`not_offered`, `budget_exhausted`).
    func recordAuditExtensionDenied(reason: String, actor: AuditActor) {
        auditLog.emit(
            .extensionDenied,
            actor: actor,
            detail: [
                "reason": .string(reason),
                "budgetRemaining": .int(extensionsRemaining),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }

    /// Records that the user submitted an override justification.
    ///
    /// The prose itself is never written — only its length and a truncated
    /// digest. The verbatim text is already persisted to `activity.sqlite3`
    /// for the retrospective; duplicating it into a plain-text log that a user
    /// might hand to support widens exposure without making the decision any
    /// more auditable.
    func recordAuditOverrideRequested(reason: String) {
        var detail = AuditRedaction.redactedDetail(reason, prefix: "reason")
        detail["budgetRemaining"] = .int(overridesRemaining)
        auditLog.emit(.overrideRequested, actor: .user, detail: detail, at: currentTime)
    }

    /// Records a granted override, its expiry, and the budget it consumed.
    func recordAuditOverrideGranted(event: OverrideEvent) {
        var detail = AuditRedaction.redactedDetail(event.reason, prefix: "reason")
        detail["minutes"] = .int(event.grantedDurationMinutes)
        detail["budgetRemaining"] = .int(overridesRemaining)
        detail["budgetLimit"] = .int(settings.overrideWeeklyLimit)
        if let overrideUntil {
            detail["activeUntil"] = .string(AuditTimestamp.string(from: overrideUntil))
        }
        auditLog.emit(.overrideGranted, actor: .user, detail: detail, at: event.timestamp)
    }

    /// Records a refused override. `reason` is a stable token
    /// (`not_locked`, `budget_exhausted`, `gate_failed`).
    func recordAuditOverrideDenied(reason: String, actor: AuditActor) {
        auditLog.emit(
            .overrideDenied,
            actor: actor,
            detail: [
                "reason": .string(reason),
                "budgetRemaining": .int(overridesRemaining),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }
}
