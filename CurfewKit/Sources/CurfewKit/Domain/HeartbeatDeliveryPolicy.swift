import Foundation

/// The app's delivery cadence, separated from its asynchronous XPC boundary.
public nonisolated enum HeartbeatDeliveryPolicy {
    public static func shouldSend(
        lastSentAt: Date?, lastObservedAt: Date? = nil, now: Date, interval: TimeInterval
    ) -> Bool {
        if let lastObservedAt, now < lastObservedAt {
            return true
        }
        if let lastSentAt, now >= lastSentAt, now.timeIntervalSince(lastSentAt) < interval {
            return false
        }
        return true
    }
}
