import Foundation

/// The existing legacy file boundary, kept separate from authenticated receipts.
public struct LegacyDaemonHeartbeatClock {
    private var clock = DaemonHeartbeatClock()

    public init() {}

    public mutating func age(heartbeatURL: URL, at now: Date) -> TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: heartbeatURL.path)
        let modified = attrs?[.modificationDate] as? Date
        let identity = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value
        return clock.age(of: modified, at: now, receiptIdentity: identity)
    }
}
