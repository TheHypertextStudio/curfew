import Foundation

/// Inert app-side contract. Implement only after observing behavioral RED.
/// Accepts locally resolved presentation plans, never restriction authority.
@MainActor
public final class SunriseWakeCoordinator {
    public enum Status: Equatable {
        case disabled
        case waitingForSchedule
        case scheduled
        case displayRequested
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

    /// Scheduled will mean helper acceptance only, never physical illumination.
    public private(set) var status: Status = .disabled

    public init(
        operations _: Operations,
        displayDelivery _: SunriseDisplayDelivery,
        cleanupNativeAssertions _: @escaping @MainActor () throws -> Void
    ) {}

    /// Existing app clock/lifecycle supplies inputs; no observers or timer owned here.
    public func reconcile(
        plan _: SunriseWakePlan?,
        enabled _: Bool = false,
        batteryOptIn _: Bool = false,
        onExternalPower _: Bool,
        now _: Date
    ) async {}
}
