import Foundation
import Observation

/// Owns cancellable presentation effects, with no restriction or unlock capability.
@Observable
@MainActor
public final class RestHandoffCoordinator {
    public struct Operations {
        public var settle: @MainActor () async throws -> Void
        public var launch: @MainActor () async -> RestHandoffPolicy.LaunchResult
        public var refreshTime: @MainActor () async -> Void
        public var refreshAuthority: @MainActor () async -> Void

        public init(
            settle: @escaping @MainActor () async throws -> Void,
            launch: @escaping @MainActor () async -> RestHandoffPolicy.LaunchResult,
            refreshTime: @escaping @MainActor () async -> Void,
            refreshAuthority: @escaping @MainActor () async -> Void
        ) {
            self.settle = settle
            self.launch = launch
            self.refreshTime = refreshTime
            self.refreshAuthority = refreshAuthority
        }
    }

    public private(set) var policy: RestHandoffPolicy
    private let operations: Operations
    private let uptime: () -> TimeInterval
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(operations: Operations, uptime: @escaping () -> TimeInterval) {
        self.operations = operations
        self.uptime = uptime
        self.policy = RestHandoffPolicy(monotonicSeconds: uptime())
    }

    @discardableResult
    public func handle(_ event: RestHandoffPolicy.Event) -> Task<Void, Never>? {
        let effects = policy.handle(event, monotonicSeconds: uptime())
        guard !effects.isEmpty else { return nil }
        task?.cancel()
        if effects.contains(where: {
            if case .cancel = $0 {
                return true
            }; return false
        }) {
            task = nil
            return nil
        }
        let work = Task { [weak self] in
            guard let self else { return }
            for effect in effects {
                guard !Task.isCancelled else { return }
                await perform(effect)
            }
        }
        task = work
        return work
    }

    private func perform(_ effect: RestHandoffPolicy.Effect) async {
        switch effect {
        case .settle(let generation):
            await enterSaver(generation)
        case .refreshTime(let generation):
            await operations.refreshTime()
            guard !Task.isCancelled else { return }
            _ = policy.handle(.timeRefreshed(generation), monotonicSeconds: uptime())
        case .refreshAuthority(let generation):
            await operations.refreshAuthority()
            guard !Task.isCancelled else { return }
            _ = policy.handle(.authorityRefreshed(generation), monotonicSeconds: uptime())
        default:
            break
        }
    }

    private func enterSaver(_ generation: RestHandoffPolicy.Generation) async {
        do {
            try await operations.settle()
            try Task.checkCancellation()
            let effects = policy.handle(.settled(generation), monotonicSeconds: uptime())
            guard effects == [.launchSaver(generation)] else { return }
            let result = await operations.launch()
            try Task.checkCancellation()
            _ = policy.handle(.launchCompleted(generation, result), monotonicSeconds: uptime())
        } catch {
            // Cancellation or failed settling restores the same retained interactive host.
            _ = policy.handle(.input, monotonicSeconds: uptime())
        }
    }

    public func reset() {
        task?.cancel()
        task = nil
        policy = RestHandoffPolicy(monotonicSeconds: uptime())
    }
}
