import Foundation

/// Inert API scaffold for behavioral failing-first tests of presentation-only handoff.
/// No event is processed until the policy's behavior has been verified failing first.
public nonisolated struct RestHandoffPolicy: Sendable {
    public typealias Generation = UInt64

    public enum ReflectionResolution: Equatable, Sendable {
        case submitted, skipped
    }

    public enum Blocker: Equatable, Sendable {
        case editing, confirmation, recovery
    }

    public enum Phase: Equatable, Sendable {
        case interactive, settling, saver, refreshing
    }

    public enum SetupStatus: Equatable, Sendable {
        case companionUnavailable, launchUnavailable
    }

    public enum LaunchResult: Equatable, Sendable {
        case started
        case unavailable(SetupStatus)
    }

    public enum Event: Equatable, Sendable {
        case reflectionResolved(ReflectionResolution)
        case idleCheck
        case input
        case setBlocker(Blocker, active: Bool)
        case restNow
        case settled(Generation)
        case launchCompleted(Generation, LaunchResult)
        case saverReturned
        case timeRefreshed(Generation)
        case authorityRefreshed(Generation)
    }

    public enum Effect: Equatable, Sendable {
        case settle(Generation)
        case cancel(Generation)
        case launchSaver(Generation)
        case refreshTime(Generation)
        case refreshAuthority(Generation)
    }

    public private(set) var pendingGeneration: Generation?
    public private(set) var phase: Phase = .interactive
    public private(set) var controlsMayReturn = true
    public private(set) var setupStatus: SetupStatus?

    public init(monotonicSeconds _: TimeInterval) {}

    public mutating func handle(
        _: Event,
        monotonicSeconds _: TimeInterval
    ) -> [Effect] {
        []
    }
}
