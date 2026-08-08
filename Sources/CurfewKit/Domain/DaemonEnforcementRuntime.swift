import Foundation

/// The side effects the privileged daemon can have on the machine.
///
/// Behind a protocol so the code that *acts* on a decision is testable. Three
/// rounds of review found three bugs on this branch and every one of them was
/// in imperative shell code that no test could reach — the pure decision
/// function was well covered while the thing that carried the decision out was
/// a top-level script. This is the seam that ends that.
public protocol DaemonEnforcementEffects: AnyObject {
    /// Writes (or deletes, for `nil`) the root-owned deferral marker.
    func persistDeferralStart(_ start: Date?)

    /// Kills a `/sbin/shutdown` this daemon already issued.
    func cancelPendingShutdown()

    /// Runs `/sbin/shutdown -h +1` as root.
    ///
    /// Throws when the command could not be launched at all. The audit record
    /// for this action is written from the result, so an implementation that
    /// swallows its own failure would make the log assert a shutdown that
    /// never happened. A non-throwing implementation still satisfies this.
    func issueShutdown() throws

    /// Removes the root-owned copy of the lockout deadline.
    func clearDeadlineShadow()
}

/// Carries out a ``DaemonEnforcementDecision/Outcome`` and holds the small
/// amount of state that survives between ticks.
///
/// `main.swift` reads the world, asks ``DaemonEnforcementDecision``, hands the
/// answer here, and logs whatever comes back. It decides nothing and it
/// performs nothing directly, which is the only arrangement under which the
/// daemon's behaviour is actually covered by tests.
public struct DaemonEnforcementRuntime {
    /// What the caller should log for this tick.
    public enum LogEvent: Equatable, Sendable {
        /// The daemon is finished with this lockout window.
        case exiting
        /// A break-glass release was honored. Emitted on the transition only,
        /// so a fifteen-second loop does not repeat itself all night.
        case standingDown
        /// A shutdown is due but protected work is holding it back.
        case holding(until: Date)
        /// The root shutdown was just issued.
        case issuedShutdown
        /// Nothing worth saying.
        case idle
    }

    /// Whether a `/sbin/shutdown` this daemon issued is still pending. Fed
    /// back into the next tick's `Input` so the decision knows not to issue a
    /// second one — and so it knows there is something to call off.
    public private(set) var shutdownIssued = false

    /// Set once the daemon should leave its loop.
    public private(set) var shouldExit = false

    /// Tracks the stand-down transition so ``LogEvent/standingDown`` is
    /// emitted once rather than on every pass.
    private var isStandingDown = false

    /// Where this runtime records what it did to the machine.
    ///
    /// The audit calls live here rather than in the loop or behind
    /// ``DaemonEnforcementEffects`` for two reasons. The same `if` that calls
    /// an effect writes the record, so the log cannot claim a cancellation
    /// that never happened or miss one that did. And the two facts a record
    /// needs — *why* a shutdown was called off, and whether a stand-down is a
    /// transition or the ninetieth identical tick — exist only here; the
    /// effects protocol carries no reason, so a decorator on it would have had
    /// to re-derive both from a second copy of this switch.
    private let auditLog: AuditLog

    /// Creates a runtime. `auditLog` defaults to the process-wide log, which
    /// is a no-op until a process bootstraps one — so tests that do not care
    /// about auditing need not mention it.
    public init(auditLog: AuditLog = .shared) {
        self.auditLog = auditLog
        // The daemon starts with no deferral window. Seeding the memo stops
        // the first tick reporting "closed" as though one had just ended.
        auditLog.seed(key: "daemonDeferralWindow", value: "none")
    }

    /// Applies `outcome`, and returns what the caller should log.
    ///
    /// - Parameter now: the tick's clock reading, stamped on the audit
    ///   records this writes so they line up with the ones `main.swift`
    ///   emits for the same tick. Defaults to the wall clock so callers that
    ///   are not exercising the audit trail need not supply it.
    @discardableResult
    public mutating func apply(
        _ outcome: DaemonEnforcementDecision.Outcome,
        effects: any DaemonEnforcementEffects,
        now: Date = Date()
    ) -> LogEvent {
        // Unconditional, including nil. A heartbeat that recovers must close
        // its window here or the next incident in this lockout inherits a
        // spent budget.
        effects.persistDeferralStart(outcome.deferralStartedAt)
        recordDeferralWindow(outcome.deferralStartedAt, now: now)

        // One site, driven by the outcome, so no action can be added later
        // that quietly forgets to call off a shutdown it just decided against.
        if outcome.cancelsPendingShutdown {
            effects.cancelPendingShutdown()
            shutdownIssued = false
            auditLog.emit(
                .daemonShutdownCancelled,
                actor: .daemon,
                detail: ["reason": .string(Self.cancellationReason(outcome.action))],
                at: now
            )
        }

        switch outcome.action {
        case .exit:
            effects.clearDeadlineShadow()
            shouldExit = true
            isStandingDown = false
            return .exiting

        case .standDown:
            let isTransition = !isStandingDown
            isStandingDown = true
            if isTransition {
                auditLog.emit(.daemonStandDown, actor: .daemon, at: now)
            }
            return isTransition ? .standingDown : .idle

        case .hold(let until):
            isStandingDown = false
            // Keyed on the bound, which is fixed for one deferral window, so
            // a hold that spans forty ticks writes one line rather than forty.
            auditLog.emitIfChanged(
                key: "daemonShutdownHold",
                to: AuditTimestamp.string(from: until),
                event: .daemonShutdownHeld,
                actor: .daemon,
                detail: [
                    "until": .string(AuditTimestamp.string(from: until)),
                    "shutdownWasInFlight": .bool(outcome.cancelsPendingShutdown)
                ],
                at: now
            )
            return .holding(until: until)

        case .shutDown:
            isStandingDown = false
            // Recorded from the outcome, not before it. Emitting `issued`
            // ahead of the call meant a launch that threw left the log
            // claiming a shutdown that never happened — the one assertion an
            // audit trail must never make about a root action.
            do {
                try effects.issueShutdown()
                auditLog.emit(.daemonShutdownIssued, actor: .daemon, at: now)
            } catch {
                auditLog.emit(
                    .daemonShutdownFailed,
                    actor: .daemon,
                    detail: ["error": .string(error.localizedDescription)],
                    at: now
                )
            }
            // Set regardless of the launch result, preserving the enforcement
            // behaviour this branch inherited: the decision suppresses a
            // second attempt for this window either way.
            shutdownIssued = true
            return .issuedShutdown

        case .wait:
            isStandingDown = false
            return .idle
        }
    }

    /// Records the bounded deferral window opening and closing.
    ///
    /// The marker is rewritten every tick by design, so this keys off the
    /// value: one line when a window opens and one when it closes, not one
    /// every fifteen seconds in between.
    private func recordDeferralWindow(_ startedAt: Date?, now: Date) {
        let token = startedAt.map { AuditTimestamp.string(from: $0) } ?? "none"
        var detail: [String: AuditValue] = [:]
        if let startedAt {
            detail["startedAt"] = .string(AuditTimestamp.string(from: startedAt))
            detail["openForSeconds"] = .int(max(0, Int(now.timeIntervalSince(startedAt))))
        }
        auditLog.emitIfChanged(
            key: "daemonDeferralWindow",
            to: token,
            event: startedAt == nil ? .daemonDeferralClosed : .daemonDeferralOpened,
            actor: .daemon,
            detail: detail,
            at: now
        )
    }

    /// Why a `/sbin/shutdown` in flight was called off, as a stable token.
    private static func cancellationReason(
        _ action: DaemonEnforcementDecision.Action
    ) -> String {
        switch action {
        case .hold: "protected_work"
        case .standDown: "break_glass"
        case .exit: "lockout_ended"
        case .shutDown, .wait: "unknown"
        }
    }
}
