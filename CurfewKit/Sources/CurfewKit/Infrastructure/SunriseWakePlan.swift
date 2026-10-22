import Foundation

/// An immutable description of one occurrence's wake event and display hold.
public struct SunriseWakePlan: Codable, Equatable, Sendable {
    public static let eventType = "wake"

    public let owner: String
    public let occurrenceID: UUID
    public let wakeAt: Date
    public let holdUntil: Date
    public let allowsBattery: Bool
}

/// Pure planning for helper-authorized occurrences; performs no power operations.
public struct SunriseWakePlanner {
    private let owner: String

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

    /// The privileged adapter supplies its fixed app-flavor namespace here.
    public init(owner: String) {
        self.owner = owner
    }

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
        guard enabled else { return nil }
        guard requestedOccurrenceID == authorizedOccurrenceID else {
            throw ValidationError.unauthorizedOccurrence
        }
        guard now.timeIntervalSince1970.isFinite,
              lockedAt.timeIntervalSince1970.isFinite,
              unlockAt.timeIntervalSince1970.isFinite
        else {
            throw ValidationError.invalidTimestamp
        }
        guard unlockAt > lockedAt else {
            throw ValidationError.invalidOccurrence
        }
        guard (5 ... 60).contains(leadMinutes) else {
            throw ValidationError.invalidLeadMinutes
        }

        let wakeAt = unlockAt.addingTimeInterval(-Double(leadMinutes) * 60)
        guard wakeAt > now else {
            throw ValidationError.expired
        }
        guard allowsBattery || onExternalPower else {
            throw ValidationError.batteryExcluded
        }

        return SunriseWakePlan(
            owner: owner,
            occurrenceID: authorizedOccurrenceID,
            wakeAt: wakeAt,
            holdUntil: unlockAt.addingTimeInterval(300),
            allowsBattery: allowsBattery
        )
    }

    public func reconcile(current: SunriseWakePlan?, desired: SunriseWakePlan?) -> Change {
        guard desired == nil || desired?.owner == owner else {
            return Change(cancel: nil, schedule: nil)
        }
        let ownedCurrent = current?.owner == owner ? current : nil
        guard ownedCurrent != desired else {
            return Change(cancel: nil, schedule: nil)
        }
        return Change(cancel: ownedCurrent, schedule: desired)
    }
}
