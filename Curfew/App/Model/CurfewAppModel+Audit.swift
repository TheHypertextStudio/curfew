import Foundation

/// Per-model audit-log override, keyed by model identity.
///
/// File-scoped rather than a stored property on `CurfewAppModel` — the same
/// pattern `CurfewAppModel+EnforcementHealth.swift` uses for its prompt flag —
/// because the model class is already at its lint-enforced line budget and
/// because production never touches this: the entry only exists when a test
/// injects a recording log. Every access is `@MainActor`, so the dictionary
/// needs no lock. Entries are not reaped on model deinit; in production the
/// map stays empty, and in tests it holds one entry per case.
private var auditLogOverrides: [ObjectIdentifier: AuditLog] = [:]

/// Audit-log emitters for `CurfewAppModel`.
///
/// Everything Curfew writes to `~/Library/Logs/Curfew/curfew-app.jsonl` from
/// the app side originates here. Two rules shape this file:
///
/// - **Nothing decides anything.** These methods only observe. If removing a
///   call changed enforcement behaviour, the call would be in the wrong place.
/// - **The tick loop gets one call.** ``recordAuditTickState(previousPhase:)``
///   folds every per-tick transition (phase, warning stage, shutdown workflow,
///   Accessibility trust, enforcement health, presence) into a single line at
///   the bottom of `tick()`, using ``AuditLog/emitIfChanged(key:to:event:actor:detail:at:)``
///   for transition detection so the model needs no new stored state.
///
/// Redaction lives at the call site, not in the writer: override reason prose
/// never leaves this file as text. See ``AuditRedaction``.
@MainActor
extension CurfewAppModel {
    /// The log these emitters write to: the process-wide stream in
    /// production, or whatever a test injected via ``auditLogOverride``.
    var auditLog: AuditLog {
        auditLogOverrides[ObjectIdentifier(self)] ?? AuditLog.shared
    }

    /// Test seam. Assigning a log here routes this model's records to it
    /// rather than the process-wide stream, so a suite can observe what was
    /// written without installing global state parallel suites would see.
    var auditLogOverride: AuditLog? {
        get { auditLogOverrides[ObjectIdentifier(self)] }
        set { auditLogOverrides[ObjectIdentifier(self)] = newValue }
    }

    // MARK: - Tick loop

    /// Records every state transition visible at the end of one tick.
    ///
    /// Called once from `tick()`. Each dimension is keyed independently, so a
    /// tick where only presence moved writes exactly one line.
    func recordAuditTickState(previousPhase: EnforcementPhase) {
        recordAuditPhaseTransition(from: previousPhase)
        recordAuditWarningStage()
        recordAuditShutdownWorkflow()
        recordAuditEnforcementHealth()
        recordAuditPresence()
    }

    /// Writes `enforcement.phase_changed` plus, where applicable, the
    /// `lockout.started` / `lockout.ended` pair that an auditor greps for
    /// first. No-ops when the phase held steady, which is almost every tick.
    private func recordAuditPhaseTransition(from previousPhase: EnforcementPhase) {
        let current = state.phase
        auditLog.seed(key: "phase", value: AuditTokens.phase(current))
        guard previousPhase != current else { return }

        let todayRule = settings.schedule.rule(for: Weekday(from: currentTime))
        var detail: [String: AuditValue] = [
            "warningStage": .string(AuditTokens.warningStage(state.warningStage)),
            "minutesRemaining": .int(min(state.minutesRemaining, Int(Int32.max))),
            "trigger": .string(state.trigger.rawValue),
            "scheduleDigest": .string(AuditScheduleSummary.digest(settings.schedule)),
            "extensionMinutesToday": .int(extensionMinutesGrantedToday),
            "snoozeMinutesToday": .int(snoozeMinutesGrantedToday)
        ]
        detail.merge(AuditScheduleSummary.ruleDetail(todayRule, prefix: "today")) { lhs, _ in lhs }
        if let lockDate = state.lockDate {
            detail["lockAt"] = .string(AuditTimestamp.string(from: lockDate))
        }
        if let unlockDate = state.unlockDate {
            detail["unlockAt"] = .string(AuditTimestamp.string(from: unlockDate))
        }

        auditLog.emit(
            .phaseChanged,
            actor: .app,
            from: AuditTokens.phase(previousPhase),
            to: AuditTokens.phase(current),
            detail: detail,
            at: currentTime
        )

        if current == .locked {
            recordAuditLockoutStarted(detail: detail)
        } else if previousPhase == .locked {
            recordAuditLockoutEnded(to: current, detail: detail)
        }
    }

    private func recordAuditLockoutStarted(detail: [String: AuditValue]) {
        var payload = detail
        // Says whether the engine put the user here or the durable record did.
        // A `working → locked` step mid-window with no schedule boundary is
        // otherwise unexplainable from the log alone, and that step is exactly
        // what the anti-bypass deadline exists to produce.
        payload["durableDeadlineActive"] = .bool(lockoutDeadlineStore.load() != nil)
        auditLog.emit(.lockoutStarted, actor: .app, detail: payload, at: currentTime)
    }

    private func recordAuditLockoutEnded(
        to phase: EnforcementPhase,
        detail: [String: AuditValue]
    ) {
        var payload = detail
        payload["reason"] = .string(lockoutEndReason(to: phase))
        auditLog.emit(.lockoutEnded, actor: .app, detail: payload, at: currentTime)
    }

    /// Distinguishes the three ways a lockout can stop, which is the question
    /// the log exists to answer: did the schedule release the user, or did
    /// they talk their way out?
    private func lockoutEndReason(to phase: EnforcementPhase) -> String {
        if let overrideUntil, currentTime < overrideUntil {
            return "override"
        }
        if phase == .dayOff {
            return "day_off"
        }
        return "schedule"
    }

    private func recordAuditWarningStage() {
        auditLog.emitIfChanged(
            key: "warningStage",
            to: AuditTokens.warningStage(state.warningStage),
            event: .warningStageChanged,
            actor: .app,
            detail: [
                "minutesRemaining": .int(min(state.minutesRemaining, Int(Int32.max))),
                "phase": .string(AuditTokens.phase(state.phase))
            ],
            at: currentTime
        )
    }

    /// Mirrors `ShutdownWorkflow.Phase` into the log. The workflow is a value
    /// type advanced inside `updateShutdownWorkflow()`; observing its phase
    /// after the fact keeps `ShutdownWorkflow` itself free of logging.
    private func recordAuditShutdownWorkflow() {
        let phase = shutdownWorkflow.phase
        guard let event = Self.auditShutdownEvent(for: phase) else {
            auditLog.seed(key: "shutdown", value: "idle")
            return
        }
        var detail: [String: AuditValue] = [
            "delayMinutes": .int(settings.autoShutdownDelayMinutes),
            "activeDevice": .bool(!isUserIdle)
        ]
        if let fireAt = Self.auditShutdownFireDate(for: phase) {
            detail["fireAt"] = .string(AuditTimestamp.string(from: fireAt))
        }
        auditLog.emitIfChanged(
            key: "shutdown",
            to: Self.auditShutdownToken(for: phase),
            event: event,
            actor: .app,
            detail: detail,
            at: currentTime
        )
    }

    private func recordAuditEnforcementHealth() {
        auditLog.emitIfChanged(
            key: "accessibility",
            to: AuditTokens.permission(isAccessibilityTrusted),
            event: .accessibilityChanged,
            actor: .system,
            at: currentTime
        )
        auditLog.emitIfChanged(
            key: "enforcementHealth",
            to: Self.auditHealthToken(for: enforcementHealth),
            event: .enforcementHealthChanged,
            actor: .app,
            detail: ["phase": .string(AuditTokens.phase(state.phase))],
            at: currentTime
        )
    }

    private func recordAuditPresence() {
        auditLog.emitIfChanged(
            key: "presence",
            to: AuditTokens.presence(isIdle: isUserIdle),
            event: .presenceChanged,
            actor: .system,
            detail: ["thresholdSeconds": .int(Int(idleWatcher.idleThresholdSeconds))],
            at: currentTime
        )
    }
}
