import Foundation

/// Measures one heartbeat source without extending its age on a backward clock correction.
/// Keep one instance per source and evaluate it on the daemon's serialized state queue.
public nonisolated struct DaemonHeartbeatClock: Sendable {
    private var lastHeartbeatAt: Date?
    private var lastReceiptIdentity: UInt64?
    private var referenceAt: Date?
    private var lastObservedAt: Date?

    public init() {}

    /// Missing heartbeats retain the caller's existing hard-stale behavior.
    /// A changed stamp establishes a new reference; an initially future stamp
    /// starts at zero age. Atomic-file callers can supply the file identity;
    /// authenticated callers reset this value after retaining a fresh receipt.
    /// The original timestamp and persisted status stay intact.
    public mutating func age(
        of heartbeatAt: Date?, at now: Date, receiptIdentity: UInt64? = nil
    ) -> TimeInterval {
        defer { lastObservedAt = now }
        guard let heartbeatAt else {
            lastHeartbeatAt = nil
            lastReceiptIdentity = nil
            referenceAt = nil
            return .infinity
        }

        if lastHeartbeatAt != heartbeatAt ||
            (receiptIdentity != nil && receiptIdentity != lastReceiptIdentity) {
            lastHeartbeatAt = heartbeatAt
            lastReceiptIdentity = receiptIdentity
            // A future persisted stamp gets the normal grace, not an immediate action
            // or a timeout extended by the whole clock skew after a daemon restart.
            referenceAt = min(heartbeatAt, now)
        } else if let lastObservedAt, now < lastObservedAt {
            referenceAt = referenceAt?.addingTimeInterval(now.timeIntervalSince(lastObservedAt))
        }
        return max(0, now.timeIntervalSince(referenceAt ?? now))
    }
}
