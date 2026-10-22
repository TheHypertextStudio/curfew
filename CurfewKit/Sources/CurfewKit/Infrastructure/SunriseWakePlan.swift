import Foundation

/// Temporary, unconsumed contract scaffold. No scheduling or validation is implemented.
public struct SunriseWakePlan: Codable, Equatable, Sendable {
    public static let eventType = "wake"

    public let owner: String
    public let occurrenceID: UUID
    public let wakeAt: Date
    public let holdUntil: Date
    public let allowsBattery: Bool
}

/// Temporary scaffold for establishing behavioral RED before implementation.
public struct SunriseWakePlanner {
    public enum ValidationError: Error, Equatable {
        case invalidLeadMinutes
        case unauthorizedOccurrence
        case invalidOccurrence
        case expired
        case batteryExcluded
        case invalidTimestamp
    }

    public struct Change {
        public let cancel: SunriseWakePlan?
        public let schedule: SunriseWakePlan?
    }

    public init(owner: String) {}

    public func makePlan(
        enabled: Bool = false,
        requestedOccurrenceID: UUID,
        authorizedOccurrenceID: UUID,
        lockedAt: Date,
        unlockAt: Date,
        leadMinutes: Int,
        allowsBattery: Bool,
        onExternalPower: Bool,
        now: Date
    ) throws -> SunriseWakePlan? {
        nil
    }

    public func reconcile(current: SunriseWakePlan?, desired: SunriseWakePlan?) -> Change {
        Change(cancel: nil, schedule: nil)
    }
}
