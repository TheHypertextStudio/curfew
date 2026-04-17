import Foundation

/// View-facing surface of `CurfewAppModel`.
///
/// Everything in this extension is a derivation of the model's stored state —
/// no side effects, no I/O. UI layers read these computed properties instead
/// of inspecting `state.phase`/`state.minutesRemaining` directly, so the
/// formatting rules (status copy, `H:MM` padding, schedule-window arrows)
/// live in one place and stay consistent across menu bar, main window,
/// lockout overlay, and widgets.
@MainActor
extension CurfewAppModel {
    /// SF Symbol name representing the current phase. Surfaces in the menu
    /// bar.
    var menuBarSymbolName: String {
        symbolName(for: state.phase)
    }

    var statusLine: String {
        statusLine(for: state.phase)
    }

    var timeRemainingText: String {
        timeRemainingText(for: state.minutesRemaining)
    }

    var snapshot: EnforcementSnapshot {
        EnforcementSnapshot(
            phase: state.phase,
            symbolName: symbolName(for: state.phase),
            statusLine: statusLine(for: state.phase),
            timeRemainingText: timeRemainingText(for: state.minutesRemaining),
            scheduleWindowText: scheduleWindowText,
            scheduleSummarySentence: scheduleSummarySentence,
            pendingScheduleDescription: pendingScheduleDescription,
            canRequestExtension: state.canRequestExtension,
            extensionRequestTitle: extensionRequestTitle,
            extensionsRemaining: extensionsRemaining
        )
    }

    var extensionRequestTitle: String {
        let holdSeconds = Int(Self.extensionConfirmationHoldSeconds)
        let minutes = settings.extensionDurationMinutes
        return "Hold \(holdSeconds)s for +\(minutes)m extension"
    }

    var editableSchedule: WeeklySchedule {
        settings.pendingScheduleChange?.proposedSchedule ?? settings.schedule
    }

    var pendingScheduleDescription: String? {
        guard let pending = settings.pendingScheduleChange else {
            return nil
        }
        let timestamp = pending.effectiveAt.formatted(date: .abbreviated, time: .shortened)
        switch pending.classification {
        case .weaker:
            return "A less strict schedule is queued for \(timestamp)."
        case .stricter:
            return "A stricter schedule is queued for \(timestamp)."
        case .noChange:
            return nil
        }
    }

    var scheduleSummarySentence: String {
        editableSchedule.summarySentence(forNextDayFrom: currentTime)
    }

    var scheduleWindowText: String {
        guard let lockDate = state.lockDate, let unlockDate = state.unlockDate else {
            return "No enforcement window is active today."
        }
        let lockText = lockDate.formatted(date: .omitted, time: .shortened)
        let unlockText = unlockDate.formatted(date: .omitted, time: .shortened)
        return "\(lockText) -> \(unlockText)"
    }

    var overrideCooldownRemaining: Int {
        guard let overrideCooldownEndsAt else {
            return 0
        }
        return max(0, Int(overrideCooldownEndsAt.timeIntervalSince(currentTime)))
    }

    var canConfirmOverride: Bool {
        OverrideRequestPolicy.canConfirm(
            reason: overrideReasonDraft,
            now: currentTime,
            cooldownEndsAt: overrideCooldownEndsAt,
            overridesRemaining: overridesRemaining
        )
    }

    func symbolName(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            "clock.badge.checkmark"
        case .warning:
            "exclamationmark.triangle"
        case .locked:
            "lock.fill"
        case .dayOff:
            "moon.zzz"
        }
    }

    func statusLine(for phase: EnforcementPhase) -> String {
        switch phase {
        case .working:
            "Working window active"
        case .warning:
            "Wrap up time"
        case .locked:
            "Curfew lockout active"
        case .dayOff:
            "Day off"
        }
    }

    func timeRemainingText(for minutesRemaining: Int) -> String {
        if minutesRemaining == .max {
            return "—"
        }
        let minutes = max(0, minutesRemaining)
        let hoursComponent = minutes / 60
        let minuteComponent = minutes % 60
        return String(format: "%d:%02d", hoursComponent, minuteComponent)
    }
}
