import Foundation

/// Helper-local reconciliation with injected journal and power-event operations.
/// The helper must serialize calls and provide atomic durable journal saves.
public final class SunriseWakeScheduler {
    /// Exact native cancellation identity; event type cannot be supplied by callers.
    public struct Event: Equatable, Sendable {
        public let owner: String
        public let wakeAt: Date
        public var eventType: String {
            SunriseWakePlan.eventType
        }

        public init(plan: SunriseWakePlan) {
            self.owner = plan.owner
            self.wakeAt = plan.wakeAt
        }
    }

    public enum RecordPhase: String, Codable, Sendable {
        case pending
        case scheduled
    }

    public struct Record: Codable, Equatable, Sendable {
        public let plan: SunriseWakePlan
        public let phase: Phase

        public init(plan: SunriseWakePlan, phase: Phase) {
            self.plan = plan
            self.phase = phase
        }
    }

    public enum Outcome: Equatable, Sendable {
        case scheduled
        case cancelled
        case unchanged
    }

    public enum Rejection: Error, Equatable {
        case unauthorizedPlan
        case foreignOwner
        case invalidTimestamp
        case expired
        case batteryExcluded
    }

    private let owner: String
    private let load: () throws -> Record?
    private let save: (Record?) throws -> Void
    private let schedule: (Event) throws -> Void
    private let cancel: (Event) throws -> Void
    private var acceptedPlan: SunriseWakePlan?

    /// The helper supplies a fixed flavor owner and serialized, durable journal
    /// operations. Native adapters must cancel by the complete Event identity;
    /// cancellation of a missing event is successful and must be idempotent.
    public init(
        owner: String,
        load: @escaping () throws -> Record?,
        save: @escaping (Record?) throws -> Void,
        schedule: @escaping (Event) throws -> Void,
        cancel: @escaping (Event) throws -> Void
    ) {
        self.owner = owner
        self.load = load
        self.save = save
        self.schedule = schedule
        self.cancel = cancel
    }

    /// `authorizedPlan` must be freshly derived inside the helper from its
    /// trusted occurrence, policy and clock; decoding is never authorization.
    /// Persist pending identity before native scheduling. On process restart,
    /// both journal phases mean unknown native state: cancel exact owned
    /// identity before rescheduling. In-process acceptance alone permits dedup.
    public func reconcile(
        desired: SunriseWakePlan?,
        authorizedPlan: SunriseWakePlan?,
        onExternalPower: Bool,
        now: Date
    ) throws -> Outcome {
        try validateAuthority(desired: desired, authorizedPlan: authorizedPlan, now: now)
        let record = try load()
        try validateRecord(record)

        if let desired, !onExternalPower, !desired.allowsBattery {
            if let record {
                acceptedPlan = nil
                try cancel(Event(plan: record.plan))
                try save(nil)
            }
            throw Rejection.batteryExcluded
        }

        if let desired, acceptedPlan == desired,
           record == Record(plan: desired, phase: .scheduled) {
            return .unchanged
        }

        if let record {
            // Until both native acceptance and final persistence succeed, every
            // journal phase is unknown native state and needs exact cancellation.
            acceptedPlan = nil
            try cancel(Event(plan: record.plan))
        } else {
            acceptedPlan = nil
        }

        guard let desired else {
            guard record != nil else { return .unchanged }
            try save(nil)
            return .cancelled
        }

        try save(Record(plan: desired, phase: .pending))
        try schedule(Event(plan: desired))
        try save(Record(plan: desired, phase: .scheduled))
        acceptedPlan = desired
        return .scheduled
    }

    private func validateAuthority(
        desired: SunriseWakePlan?, authorizedPlan: SunriseWakePlan?, now: Date
    ) throws {
        // Even cancellation requests must match fresh helper authority before
        // reading the journal or invoking any injected operation.
        guard desired == authorizedPlan else { throw Rejection.unauthorizedPlan }
        if let desired {
            guard desired.owner == owner else { throw Rejection.foreignOwner }
            try validateTimestamps(desired)
            guard now.timeIntervalSince1970.isFinite else { throw Rejection.invalidTimestamp }
            guard desired.wakeAt > now else { throw Rejection.expired }
        }
    }

    private func validateRecord(_ record: Record?) throws {
        if let record {
            guard record.plan.owner == owner else { throw Rejection.foreignOwner }
            try validateTimestamps(record.plan)
        }
    }

    private func validateTimestamps(_ plan: SunriseWakePlan) throws {
        guard plan.wakeAt.timeIntervalSince1970.isFinite,
              plan.holdUntil.timeIntervalSince1970.isFinite,
              plan.holdUntil > plan.wakeAt
        else {
            throw Rejection.invalidTimestamp
        }
    }
}

public extension SunriseWakeScheduler.Record {
    typealias Phase = SunriseWakeScheduler.RecordPhase
}
