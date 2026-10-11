import Foundation

/// The one place that decides whether a destructive enforcement action may run.
///
/// Two paths end processes — `ShutdownWorkflow`'s terminate-and-power-off
/// sequence in the app, and the privileged daemon's `/sbin/shutdown`. They run
/// in different processes, on different triggers, at different privilege
/// levels, and the entire point of the carve-out is that they must never
/// disagree about whether it is safe to kill the user's background work.
///
/// Sharing a helper is not enough for that. The first cut of this branch had
/// both paths consulting ``ProtectedWorkDeferral`` and they *still* drifted:
/// the app treated a break-glass release as terminal for the rest of the
/// lockout window while the daemon re-checked it every tick, so revoking a
/// release re-armed the daemon and left the app permanently stood down. The
/// answers matched until the question changed.
///
/// So the whole question lives here, break-glass included, and both callers
/// ask it the same way. Anything either path decides on its own is a place
/// they can drift again.
public struct DestructiveActionGate: Equatable, Sendable {
    /// What the caller may do right now.
    public enum Decision: Equatable, Sendable {
        /// A verified break-glass release covers this window. Do not act, and
        /// undo anything already in flight.
        case standDown
        /// Protected work is live. Hold until `until` at the latest.
        case hold(until: Date)
        /// Nothing is holding the action back.
        case proceed
    }

    /// The bounded deferral window. Exposed so the daemon can persist and
    /// restore ``ProtectedWorkDeferral/startedAt`` across process restarts;
    /// the app keeps it in memory because a relaunch rebuilds the workflow.
    public private(set) var deferral: ProtectedWorkDeferral

    /// When the current deferral window opened, or `nil` when none is open.
    /// The daemon writes exactly this to its root-owned marker every tick.
    public var deferralStartedAt: Date? {
        deferral.startedAt
    }

    /// Creates a gate, optionally resuming a window a previous process opened.
    public init(deferralStartedAt: Date? = nil) {
        self.deferral = ProtectedWorkDeferral(startedAt: deferralStartedAt)
    }

    /// Decides, and advances the deferral window's bookkeeping.
    ///
    /// - Parameters:
    ///   - now: current clock time.
    ///   - isDue: whether the destructive action is due at all. The app passes
    ///     `true` because it only asks once its scheduled delay has elapsed;
    ///     the daemon passes `heartbeatAge > timeout`.
    ///   - isBreakGlassActive: whether a verified release covers this window.
    ///     Re-read every tick by both callers, so revoking one re-arms both.
    ///   - hasActiveProtectedWork: whether work is in flight — an unexpired
    ///     ``ProtectedWorkClaim``, or something ``LiveProtectedWorkMonitor``
    ///     observed running. Both callers combine the two through
    ///     ``ProtectedWorkStores/hasProtectedWork(now:policy:)``.
    ///   - maximumDeferral: from ``ProtectedWorkPolicy/maximumDeferral``.
    public mutating func evaluate(
        now: Date,
        isDue: Bool,
        isBreakGlassActive: Bool,
        hasActiveProtectedWork: Bool,
        maximumDeferral: TimeInterval
    ) -> Decision {
        guard !isBreakGlassActive else {
            // A release stands the action down entirely, so there is nothing
            // left to defer. Clearing the window here is what makes a revoke
            // hand back a full grace period rather than a spent one.
            deferral = ProtectedWorkDeferral()
            return .standDown
        }

        // The conjunction closes the window the moment the action stops being
        // due — a recovered app heartbeat, in the daemon's case — so a later
        // incident in the same lockout gets its own budget instead of
        // inheriting a spent one.
        switch deferral.evaluate(
            now: now,
            hasActiveWork: isDue && hasActiveProtectedWork,
            maximumDeferral: maximumDeferral
        ) {
        case .deferred(let until):
            return .hold(until: until)
        case .proceed:
            return .proceed
        }
    }
}
