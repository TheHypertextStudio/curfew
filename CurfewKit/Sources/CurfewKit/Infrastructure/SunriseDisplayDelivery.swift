import Foundation

/// Inert contract scaffold. A later adapter supplies native power operations.
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
        case notImplemented
    }

    public var isActive: Bool {
        false
    }

    public init(
        declareUserActivity: @escaping () throws -> Void,
        acquireDisplayAssertion: @escaping (_ untilDate: Date) throws -> AssertionToken,
        releaseDisplayAssertion: @escaping (AssertionToken) throws -> Void
    ) {
        // Intentionally do not retain or invoke effects until observed RED.
    }

    public func reconcile(
        plan: SunriseWakePlan?,
        enabled: Bool = false,
        batteryOptIn: Bool = false,
        onExternalPower: Bool,
        now: Date
    ) throws -> Outcome {
        throw Rejection.notImplemented
    }

    public func dismiss(occurrenceID: UUID) throws {
        throw Rejection.notImplemented
    }

    /// Explicit teardown also supports uninstall cleanup without touching foreign assertions.
    public func stop() throws {
        throw Rejection.notImplemented
    }
}
