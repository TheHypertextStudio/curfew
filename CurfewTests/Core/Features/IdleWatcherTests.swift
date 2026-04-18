@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for `IdleWatcher`. Uses a stub clock source so tests
/// never depend on real HID activity.
@MainActor
struct IdleWatcherTests {
    @Test("Watcher reports active state when idle time is below threshold")
    func activeWhenBelowThreshold() {
        let source = StubIdleSource(seconds: 30)
        let watcher = IdleWatcher(
            source: source,
            idleThresholdSeconds: 300
        )
        #expect(!watcher.isIdle)
    }

    @Test("Watcher reports idle state when idle time is at or above threshold")
    func idleAtThreshold() {
        let source = StubIdleSource(seconds: 300)
        let watcher = IdleWatcher(
            source: source,
            idleThresholdSeconds: 300
        )
        #expect(watcher.isIdle)
    }

    @Test("Watcher observes threshold boundary crossings in both directions")
    func transitionDetection() {
        let source = StubIdleSource(seconds: 10)
        let watcher = IdleWatcher(
            source: source,
            idleThresholdSeconds: 300
        )
        var transitions: [Bool] = []
        watcher.onIdleStateChanged = { transitions.append($0) }

        watcher.sample()
        #expect(transitions.isEmpty)

        source.seconds = 400
        watcher.sample()
        #expect(transitions == [true])

        source.seconds = 5
        watcher.sample()
        #expect(transitions == [true, false])
    }
}

private final class StubIdleSource: IdleTimeSource {
    var seconds: TimeInterval

    init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    func secondsSinceLastInput() -> TimeInterval {
        seconds
    }
}
