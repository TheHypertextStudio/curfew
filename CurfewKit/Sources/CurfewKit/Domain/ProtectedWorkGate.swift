import Foundation

/// Bounded postponement of a destructive enforcement action while delegated
/// work is in flight.
///
/// Both kill paths use this: `ShutdownWorkflow` before it terminates other
/// applications, and the privileged daemon before it issues `/sbin/shutdown`.
/// Sharing one value type is what keeps the two answers consistent — a user
/// who reads the deferral rule in the app is reading the daemon's rule too.
///
/// The bound is measured from the moment the action *first came due*, not from
/// the most recent claim. Measuring from the latest claim would let an agent
/// that keeps renewing hold enforcement off forever, which is the failure this
/// type exists to prevent. Once `maximumDeferral` has elapsed the gate returns
/// ``Decision/proceed`` no matter how fresh the claim is.
///
/// The caller owns persistence of ``startedAt``. The app keeps it in memory
/// because a relaunch re-derives the whole workflow anyway; the daemon writes
/// it to a root-owned file so restarting the daemon cannot rewind the clock.
public struct ProtectedWorkDeferral: Equatable, Sendable {
    /// What the caller should do now.
    public enum Decision: Equatable, Sendable {
        /// Nothing is holding the action back. Go ahead.
        case proceed
        /// Protected work is live and the bound has not been spent. Try again
        /// after `until` at the latest.
        case deferred(until: Date)
    }

    /// When this deferral window opened, or `nil` when the action has never
    /// been deferred. Exposed so the daemon can persist and restore it.
    public private(set) var startedAt: Date?

    /// Creates a deferral, optionally resuming one that a previous process
    /// already opened.
    public init(startedAt: Date? = nil) {
        self.startedAt = startedAt
    }

    /// Decides whether the destructive action may run, and advances the
    /// window's bookkeeping.
    ///
    /// - Parameters:
    ///   - now: current clock time.
    ///   - hasActiveWork: whether any unexpired ``ProtectedWorkClaim`` exists.
    ///   - maximumDeferral: the bound, from ``ProtectedWorkPolicy/maximumDeferral``.
    /// - Returns: ``Decision/proceed`` when the action may run.
    public mutating func evaluate(
        now: Date,
        hasActiveWork: Bool,
        maximumDeferral: TimeInterval
    ) -> Decision {
        guard hasActiveWork, maximumDeferral > 0 else {
            startedAt = nil
            return .proceed
        }

        let windowStart = startedAt ?? now
        startedAt = windowStart

        let limit = windowStart.addingTimeInterval(maximumDeferral)
        guard now < limit else {
            // Bound spent. Leave `startedAt` set so a claim filed one second
            // later cannot open a fresh window on the same due action.
            return .proceed
        }
        return .deferred(until: limit)
    }

    /// Human-readable one-liner for the lockout screen and the CLI, or `nil`
    /// when nothing is being deferred.
    public func statusLine(now: Date, decision: Decision) -> String? {
        guard case .deferred(let until) = decision else {
            return nil
        }
        let remaining = max(0, Int(until.timeIntervalSince(now)) / 60)
        return "Protected work in progress — shutdown held for up to \(remaining) more min."
    }
}
