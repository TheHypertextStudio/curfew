import Foundation

/// Reconciles helper scheduling and independent local display delivery.
/// Accepts locally resolved presentation plans, never restriction authority.
@MainActor
public final class SunriseWakeCoordinator {
    public enum Status: Equatable {
        case disabled
        case waitingForSchedule
        case scheduled
        case displayRequested
        case dismissed
        case helperUnavailable
        case requestRejected
        case batteryExcluded
    }

    public enum HelperFailure: Error, Equatable {
        case unavailable
        case rejected
    }

    public struct Operations {
        public let replace: @MainActor (SunriseWakePlan) async throws -> Void
        public let cancel: @MainActor () async throws -> Void

        public init(
            replace: @escaping @MainActor (SunriseWakePlan) async throws -> Void,
            cancel: @escaping @MainActor () async throws -> Void
        ) {
            self.replace = replace
            self.cancel = cancel
        }
    }

    /// Scheduled means helper acceptance only, never physical illumination.
    public private(set) var status: Status = .disabled

    private let operations: Operations
    private let displayDelivery: SunriseDisplayDelivery
    private let cleanupNativeAssertions: @MainActor () throws -> Void
    private var helperPlan: SunriseWakePlan?
    private var helperEpoch: UInt64 = 0
    private var currentPlan: SunriseWakePlan?
    private var lastReconciledAt: Date?
    private var dismissedOccurrences: Set<UUID> = []
    private var cancellationAccepted = false
    private var cleanupPending = false
    private var revision: UInt64 = 0
    private var pending: Task<Void, Never>?

    public init(
        operations: Operations,
        displayDelivery: SunriseDisplayDelivery,
        cleanupNativeAssertions: @escaping @MainActor () throws -> Void
    ) {
        self.operations = operations
        self.displayDelivery = displayDelivery
        self.cleanupNativeAssertions = cleanupNativeAssertions
    }

    /// Existing app clock/lifecycle supplies inputs; no observers or timer owned here.
    public func reconcile(
        plan: SunriseWakePlan?,
        enabled: Bool = false,
        batteryOptIn: Bool = false,
        onExternalPower: Bool,
        now: Date
    ) async {
        currentPlan = plan
        lastReconciledAt = now
        revision &+= 1
        let currentRevision = revision
        let desiredStatus = eligibility(
            plan: plan, enabled: enabled, batteryOptIn: batteryOptIn,
            onExternalPower: onExternalPower, now: now
        )
        let futurePlan = desiredStatus == .scheduled ? plan : nil
        var displayFailed = cleanDisplay(for: desiredStatus)
        // Display eligibility is evaluated and applied before the first suspension.
        // Helper latency cannot consume this window or replay stale time after it.
        if desiredStatus == .displayRequested, !displayFailed {
            do {
                _ = try displayDelivery.reconcile(
                    plan: plan, enabled: enabled, batteryOptIn: batteryOptIn,
                    onExternalPower: onExternalPower, now: now
                )
            } catch {
                displayFailed = true
            }
        }
        status = displayFailed ? .requestRejected : pendingStatus(for: desiredStatus)
        let deliveryFailed = displayFailed
        let predecessor = pending
        let task = Task { @MainActor in
            await predecessor?.value
            guard currentRevision == self.revision else { return }
            let helperFailure = await self.updateHelper(plan: futurePlan)
            guard currentRevision == self.revision else { return }
            self.status = deliveryFailed ? .requestRejected : (helperFailure ?? desiredStatus)
        }
        pending = task
        await task.value
        if currentRevision == revision {
            pending = nil
        }
    }

    public func dismissCurrentOccurrence(at time: Date? = nil) throws {
        guard let plan = currentPlan, let now = time ?? lastReconciledAt,
              now.timeIntervalSince1970.isFinite, now >= plan.wakeAt,
              now < plan.holdUntil else { return }
        dismissedOccurrences.insert(plan.occurrenceID)
        var failure: (any Error)?
        do {
            try displayDelivery.dismiss(occurrenceID: plan.occurrenceID)
        } catch {
            failure = error
        }
        do { try cleanupNativeAssertions() } catch { failure = failure ?? error }
        cleanupPending = failure != nil
        if let failure {
            status = .requestRejected
            throw failure
        }
        status = .dismissed
    }

    /// A cancelled/removed helper must not retain an earlier acceptance receipt.
    /// In-flight old replies cannot repopulate this new ownership epoch.
    public func invalidateHelperAcceptance() {
        revision &+= 1
        helperEpoch &+= 1
        helperPlan = nil
        cancellationAccepted = false
        do {
            try dismissCurrentOccurrence()
            status = .helperUnavailable
        } catch {
            status = .requestRejected
        }
    }

    private func pendingStatus(for desiredStatus: Status) -> Status {
        if desiredStatus == .scheduled {
            return .waitingForSchedule
        }
        return desiredStatus
    }

    private func eligibility(
        plan: SunriseWakePlan?, enabled: Bool, batteryOptIn: Bool,
        onExternalPower: Bool, now: Date
    ) -> Status {
        guard enabled else { return .disabled }
        guard let plan else { return .waitingForSchedule }
        guard now.timeIntervalSince1970.isFinite,
              plan.wakeAt.timeIntervalSince1970.isFinite,
              plan.holdUntil.timeIntervalSince1970.isFinite,
              plan.wakeAt < plan.holdUntil
        else { return .requestRejected }
        guard !dismissedOccurrences.contains(plan.occurrenceID) else { return .dismissed }
        guard onExternalPower || (batteryOptIn && plan.allowsBattery) else {
            return .batteryExcluded
        }
        guard now < plan.holdUntil else { return .waitingForSchedule }
        return now < plan.wakeAt ? .scheduled : .displayRequested
    }

    /// Teardown precedes the first suspension, even while an older helper call runs.
    private func cleanDisplay(for desiredStatus: Status) -> Bool {
        guard cleanupPending || desiredStatus != .displayRequested,
              cleanupPending || desiredStatus != .scheduled || displayDelivery.isActive else {
            return false
        }
        var failed = false
        do {
            try displayDelivery.stop()
        } catch {
            failed = true
        }
        do {
            try cleanupNativeAssertions()
        } catch {
            failed = true
        }
        cleanupPending = failed
        return failed
    }

    /// Only this serialized lane mutates helper ownership, including stale results.
    /// Failure is retried by the next explicit reconcile, never a background loop.
    private func updateHelper(plan: SunriseWakePlan?) async -> Status? {
        let epoch = helperEpoch
        do {
            if let plan {
                guard helperPlan != plan else { return nil }
                cancellationAccepted = false
                helperPlan = nil
                try await operations.replace(plan)
                guard epoch == helperEpoch else { return .helperUnavailable }
                helperPlan = plan
            } else if !cancellationAccepted {
                try await operations.cancel()
                guard epoch == helperEpoch else { return .helperUnavailable }
                helperPlan = nil
                cancellationAccepted = true
            }
            return nil
        } catch HelperFailure.unavailable {
            return .helperUnavailable
        } catch {
            return .requestRejected
        }
    }
}
