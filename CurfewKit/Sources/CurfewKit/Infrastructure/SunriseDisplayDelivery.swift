import Foundation

/// Serialized display-delivery policy with injected, bounded power operations.
/// The caller must reconcile on lifecycle, timer and power changes.
/// Display delivery has no enforcement, override, authentication or unlock input.
public final class SunriseDisplayDelivery {
    public struct AssertionToken: Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
    }

    public enum Outcome: Equatable {
        case inactive
        case active
        case batteryExcluded
        case dismissed
    }

    public enum Rejection: Error, Equatable {
        case invalidTimestamp
    }

    private let declareUserActivity: () throws -> Void
    private let acquireDisplayAssertion: (Date) throws -> AssertionToken
    private let releaseDisplayAssertion: (AssertionToken) throws -> Void
    private var ownedAssertion: (token: AssertionToken, plan: SunriseWakePlan)?
    private var activityOccurrences: Set<UUID> = []
    private var deliveredOccurrences: Set<UUID> = []
    private var dismissedOccurrences: Set<UUID> = []

    /// Presentation eligibility only. False does not prove physical assertion
    /// release: a failed release retains its owned token for the next retry.
    public private(set) var isActive = false

    public init(
        declareUserActivity: @escaping () throws -> Void,
        acquireDisplayAssertion: @escaping (_ untilDate: Date) throws -> AssertionToken,
        releaseDisplayAssertion: @escaping (AssertionToken) throws -> Void
    ) {
        self.declareUserActivity = declareUserActivity
        self.acquireDisplayAssertion = acquireDisplayAssertion
        self.releaseDisplayAssertion = releaseDisplayAssertion
    }

    public func reconcile(
        plan: SunriseWakePlan?,
        enabled: Bool = false,
        batteryOptIn: Bool = false,
        onExternalPower: Bool,
        now: Date
    ) throws -> Outcome {
        guard now.timeIntervalSince1970.isFinite else {
            try stop()
            throw Rejection.invalidTimestamp
        }
        guard enabled, let plan else {
            try stop()
            return .inactive
        }
        if let outcome = try ineligibleOutcome(
            plan: plan, batteryOptIn: batteryOptIn, onExternalPower: onExternalPower, now: now
        ) {
            return outcome
        }

        if let ownedAssertion {
            if isActive,
               ownedAssertion.plan.occurrenceID == plan.occurrenceID,
               ownedAssertion.plan.holdUntil == plan.holdUntil {
                return .active
            }
            // Retain whether this is an in-flight deadline replacement before
            // releasing. A failed release must block every new native effect.
            let replacingDeadline = ownedAssertion.plan.occurrenceID == plan
                .occurrenceID && isActive
            if replacingDeadline {
                deliveredOccurrences.remove(plan.occurrenceID)
            }
            try stop()
        }
        guard !deliveredOccurrences.contains(plan.occurrenceID) else {
            return .inactive
        }
        if !activityOccurrences.contains(plan.occurrenceID) {
            try declareUserActivity()
            activityOccurrences.insert(plan.occurrenceID)
        }
        let token = try acquireDisplayAssertion(plan.holdUntil)
        ownedAssertion = (token, plan)
        deliveredOccurrences.insert(plan.occurrenceID)
        isActive = true
        return .active
    }

    private func ineligibleOutcome(
        plan: SunriseWakePlan, batteryOptIn: Bool, onExternalPower: Bool, now: Date
    ) throws -> Outcome? {
        guard plan.wakeAt.timeIntervalSince1970.isFinite,
              plan.holdUntil.timeIntervalSince1970.isFinite,
              plan.wakeAt < plan.holdUntil
        else {
            try stop()
            throw Rejection.invalidTimestamp
        }
        guard !dismissedOccurrences.contains(plan.occurrenceID) else {
            try stop()
            return .dismissed
        }
        guard now >= plan.wakeAt, now < plan.holdUntil else {
            try stop()
            return .inactive
        }
        guard onExternalPower || (plan.allowsBattery && batteryOptIn) else {
            try stop()
            return .batteryExcluded
        }

        return nil
    }

    public func dismiss(occurrenceID: UUID) throws {
        dismissedOccurrences.insert(occurrenceID)
        if ownedAssertion?.plan.occurrenceID == occurrenceID {
            try stop()
        }
    }

    /// Explicit teardown also supports uninstall cleanup without touching foreign assertions.
    public func stop() throws {
        isActive = false
        guard let ownedAssertion else { return }
        try releaseDisplayAssertion(ownedAssertion.token)
        self.ownedAssertion = nil
    }
}
