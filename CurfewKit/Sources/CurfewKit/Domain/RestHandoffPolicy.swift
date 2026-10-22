import Foundation

/// Presentation-only handoff decisions. Effects carry no enforcement authority.
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

    private var lastActivity: TimeInterval?
    private var reflectionResolved = false
    private var blockers: [Blocker] = []
    private var generation: Generation = 0
    private var launchRequested = false
    private var refreshedTime = false
    private var refreshedAuthority = false

    public init(monotonicSeconds: TimeInterval) {
        if monotonicSeconds.isFinite, monotonicSeconds >= 0 {
            self.lastActivity = monotonicSeconds
        }
    }

    public mutating func handle(
        _ event: Event,
        monotonicSeconds: TimeInterval
    ) -> [Effect] {
        switch event {
        case .reflectionResolved:
            guard phase == .interactive, !reflectionResolved else { return [] }
            reflectionResolved = true
            recordActivity(monotonicSeconds)
        case .input:
            recordActivity(monotonicSeconds)
            if phase == .settling {
                return cancelHandoff()
            }
        case .setBlocker(let blocker, let active):
            if active {
                if !blockers.contains(blocker) {
                    blockers.append(blocker)
                }
                recordActivity(monotonicSeconds)
                if phase == .settling {
                    return cancelHandoff()
                }
            } else {
                blockers.removeAll { $0 == blocker }
                recordActivity(monotonicSeconds)
            }
        case .idleCheck:
            guard let lastActivity,
                  monotonicSeconds.isFinite,
                  monotonicSeconds >= lastActivity,
                  monotonicSeconds - lastActivity >= 60
            else { return [] }
            return beginHandoff()
        case .restNow:
            return beginHandoff()
        case .settled(let callback):
            guard phase == .settling, pendingGeneration == callback, !launchRequested
            else { return [] }
            launchRequested = true
            return [.launchSaver(callback)]
        case .launchCompleted(let callback, let result):
            guard phase == .settling, pendingGeneration == callback, launchRequested
            else { return [] }
            launchRequested = false
            switch result {
            case .started:
                phase = .saver
                controlsMayReturn = false
            case .unavailable(let status):
                setupStatus = status
                pendingGeneration = nil
                phase = .interactive
                controlsMayReturn = true
                recordActivity(monotonicSeconds)
            }
        case .saverReturned:
            guard phase == .saver else { return [] }
            let refresh = nextGeneration()
            pendingGeneration = refresh
            phase = .refreshing
            controlsMayReturn = false
            refreshedTime = false
            refreshedAuthority = false
            return [.refreshTime(refresh), .refreshAuthority(refresh)]
        case .timeRefreshed(let callback):
            guard phase == .refreshing, pendingGeneration == callback else { return [] }
            refreshedTime = true
            finishRefresh(monotonicSeconds)
        case .authorityRefreshed(let callback):
            guard phase == .refreshing, pendingGeneration == callback else { return [] }
            refreshedAuthority = true
            finishRefresh(monotonicSeconds)
        }
        return []
    }

    private mutating func recordActivity(_ sample: TimeInterval) {
        guard sample.isFinite, sample >= 0 else { return }
        lastActivity = max(lastActivity ?? sample, sample)
    }

    private mutating func nextGeneration() -> Generation {
        generation += 1
        return generation
    }

    private mutating func beginHandoff() -> [Effect] {
        guard phase == .interactive, reflectionResolved, blockers.isEmpty else { return [] }
        let request = nextGeneration()
        pendingGeneration = request
        phase = .settling
        setupStatus = nil
        launchRequested = false
        return [.settle(request)]
    }

    private mutating func cancelHandoff() -> [Effect] {
        guard let pendingGeneration else { return [] }
        self.pendingGeneration = nil
        phase = .interactive
        launchRequested = false
        return [.cancel(pendingGeneration)]
    }

    private mutating func finishRefresh(_ sample: TimeInterval) {
        guard refreshedTime, refreshedAuthority else { return }
        pendingGeneration = nil
        phase = .interactive
        controlsMayReturn = true
        recordActivity(sample)
    }
}
