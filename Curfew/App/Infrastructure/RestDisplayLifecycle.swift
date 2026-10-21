import CoreGraphics
import Foundation
import Observation

enum RestDisplayEvent {
    case hidden, wakeObserved, visible, removed
}

enum RestRevealDecision: Equatable {
    case none, arm, begin, cancel
}

/// A deterministic lifecycle independent of timers and restriction authority.
/// Duplicate screen/system notifications cannot replay an already consumed reveal.
struct RestDisplayLifecycle {
    private struct State {
        var hidden = false
        var armed = false
    }

    private var states: [CGDirectDisplayID: State] = [:]

    func isVisible(for id: CGDirectDisplayID) -> Bool {
        !(states[id]?.hidden ?? false)
    }

    mutating func handle(
        _ event: RestDisplayEvent, for id: CGDirectDisplayID
    ) -> RestRevealDecision {
        var state = states[id] ?? State()
        let decision: RestRevealDecision
        switch event {
        case .hidden:
            state.hidden = true
            state.armed = false
            decision = .none
        case .wakeObserved:
            if state.hidden, !state.armed {
                state.armed = true
                decision = .arm
            } else {
                decision = .none
            }
        case .visible:
            guard !state.hidden || state.armed else { return .none }
            decision = state.hidden && state.armed ? .begin : .none
            state.hidden = false
            state.armed = false
        case .removed:
            states.removeValue(forKey: id)
            return .cancel
        }
        states[id] = state
        return decision
    }
}

/// Per-display rendering state. A cover stays opaque while the presentation
/// cannot be seen; the view consumes each reveal generation exactly once.
@Observable
final class RestDisplayPresentation {
    var isVisible = true
    var revealGeneration = 0
}
