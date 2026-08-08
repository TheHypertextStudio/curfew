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
    func issueShutdown()

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

    public init() {}

    /// Applies `outcome`, and returns what the caller should log.
    @discardableResult
    public mutating func apply(
        _ outcome: DaemonEnforcementDecision.Outcome,
        effects: any DaemonEnforcementEffects
    ) -> LogEvent {
        // Unconditional, including nil. A heartbeat that recovers must close
        // its window here or the next incident in this lockout inherits a
        // spent budget.
        effects.persistDeferralStart(outcome.deferralStartedAt)

        // One site, driven by the outcome, so no action can be added later
        // that quietly forgets to call off a shutdown it just decided against.
        if outcome.cancelsPendingShutdown {
            effects.cancelPendingShutdown()
            shutdownIssued = false
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
            return isTransition ? .standingDown : .idle

        case .hold(let until):
            isStandingDown = false
            return .holding(until: until)

        case .shutDown:
            isStandingDown = false
            effects.issueShutdown()
            shutdownIssued = true
            return .issuedShutdown

        case .wait:
            isStandingDown = false
            return .idle
        }
    }
}
