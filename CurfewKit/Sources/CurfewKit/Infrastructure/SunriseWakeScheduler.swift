import Foundation

/// INERT contract scaffold. No native power operation or persistence occurs.
/// Implement only after the behavioral contract has produced an observed RED.
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

    public struct Record: Codable, Equatable, Sendable {
        public enum Phase: String, Codable, Sendable {
            case pending
            case scheduled
        }

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
        case notImplemented
    }

    /// The helper supplies a fixed flavor owner and serialized, durable journal
    /// operations. Native adapters must cancel by the complete Event identity;
    /// cancellation of a missing event is successful and must be idempotent.
    public init(
        owner _: String,
        load _: @escaping () throws -> Record?,
        save _: @escaping (Record?) throws -> Void,
        schedule _: @escaping (Event) throws -> Void,
        cancel _: @escaping (Event) throws -> Void
    ) {}

    /// `authorizedPlan` must be freshly derived inside the helper from its
    /// trusted occurrence, policy and clock; decoding is never authorization.
    /// Persist pending identity before native scheduling. On process restart,
    /// both journal phases mean unknown native state: cancel exact owned
    /// identity before rescheduling. In-process acceptance alone permits dedup.
    public func reconcile(
        desired _: SunriseWakePlan?,
        authorizedPlan _: SunriseWakePlan?,
        onExternalPower _: Bool,
        now _: Date
    ) throws -> Outcome {
        throw Rejection.notImplemented
    }
}
