/// Monotonic, independently scheduled sync work. Socket hints are invalidations,
/// never authority or acknowledgements of HTTP reconciliation.
public struct AccountSyncReconciliationSchedule {
    public enum Channel: CaseIterable, Hashable, Sendable {
        case commands, overrides, wake, peers, results
    }

    private struct State {
        var nextDue: Duration = .zero
        var lastStart: Duration?
        var retryNotBefore: Duration = .zero
        var inFlight = false
        var dirty = false
        var failures = 0
    }

    private var states: [Channel: State] = [:]
    private let intervalOverride: Duration?

    public init(intervalOverride: Duration? = nil) {
        self.intervalOverride = intervalOverride
    }

    public mutating func beginDue(at time: Duration) -> [Channel] {
        var due: [Channel] = []
        for channel in Channel.allCases {
            var state = states[channel, default: State()]
            guard !state.inFlight, time >= state.nextDue,
                  time >= state.retryNotBefore else { continue }
            state.inFlight = true
            state.dirty = false
            state.lastStart = time
            state.nextDue = time + interval(for: channel)
            states[channel] = state
            due.append(channel)
        }
        return due
    }

    public mutating func invalidate(at time: Duration) {
        for channel in Channel.allCases where channel != .results {
            var state = states[channel, default: State()]
            state.dirty = true
            let earliest = state.lastStart.map { $0 + minimumSpacing } ?? time
            state.nextDue = min(state.nextDue, max(time, earliest))
            states[channel] = state
        }
    }

    public mutating func finish(_ channel: Channel, at time: Duration, succeeded: Bool) {
        guard var state = states[channel], state.inFlight else { return }
        state.inFlight = false
        if succeeded {
            state.failures = 0
            state.retryNotBefore = .zero
            if state.dirty {
                state.nextDue = max(time, (state.lastStart ?? time) + minimumSpacing)
            } else {
                state.nextDue = max(time, state.nextDue)
            }
        } else {
            state.failures = min(state.failures + 1, 6)
            let delay = min(
                interval(for: channel),
                .seconds(15 * (1 << (state.failures - 1)))
            )
            state.retryNotBefore = time + delay
            state.nextDue = state.retryNotBefore
        }
        states[channel] = state
    }

    private var minimumSpacing: Duration {
        min(intervalOverride ?? .seconds(10), .seconds(10))
    }

    private func interval(for channel: Channel) -> Duration {
        if let intervalOverride {
            return intervalOverride
        }
        switch channel {
        case .commands: return .seconds(60)
        case .results: return .seconds(15)
        case .overrides, .wake, .peers: return .seconds(300)
        }
    }
}
