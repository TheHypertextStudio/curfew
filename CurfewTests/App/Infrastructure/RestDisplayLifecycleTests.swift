@testable import Curfew
import Testing

struct RestDisplayLifecycleTests {
    @Test("A newly connected display begins covered until its first visible reveal")
    @MainActor
    func newDisplayStartsCovered() {
        let presentation = RestDisplayPresentation()
        #expect(!presentation.isVisible)
        #expect(presentation.revealGeneration == 0)
    }

    @Test("Each display waits for its own reported power state")
    func unequalDisplayWakeWaitsIndependently() {
        var lifecycle = RestDisplayLifecycle()
        _ = lifecycle.handle(.hidden, for: 1)
        _ = lifecycle.handle(.hidden, for: 2)
        #expect(lifecycle.observeVisibleDisplay(isAwake: true, for: 1) == .begin)
        #expect(lifecycle.observeVisibleDisplay(isAwake: false, for: 2) == .none)
        #expect(!lifecycle.isVisible(for: 2))
        #expect(lifecycle.observeVisibleDisplay(isAwake: true, for: 1) == .none)
        #expect(lifecycle.observeVisibleDisplay(isAwake: true, for: 2) == .begin)
    }

    @Test("A wake behind authentication waits until the scene can be visible")
    func hiddenWakeWaitsForVisibility() {
        var lifecycle = RestDisplayLifecycle()
        #expect(lifecycle.handle(.hidden, for: 1) == .none)
        #expect(lifecycle.handle(.wakeObserved, for: 1) == .arm)
        #expect(lifecycle.handle(.wakeObserved, for: 1) == .none)
        #expect(lifecycle.handle(.visible, for: 1) == .begin)
        #expect(lifecycle.handle(.visible, for: 1) == .none)
    }

    @Test("Activation and duplicate wake cannot replay a completed reveal")
    func duplicateWakeBeginsOnce() {
        var lifecycle = RestDisplayLifecycle()
        #expect(lifecycle.handle(.visible, for: 1) == .none)
        _ = lifecycle.handle(.hidden, for: 1)
        _ = lifecycle.handle(.wakeObserved, for: 1)
        #expect(lifecycle.handle(.visible, for: 1) == .begin)
        #expect(lifecycle.handle(.wakeObserved, for: 1) == .none)
        #expect(lifecycle.handle(.visible, for: 1) == .none)
    }

    @Test("A returning display does not restart other displays")
    func oneDisplayWakeDoesNotRestartOthers() {
        var lifecycle = RestDisplayLifecycle()
        _ = lifecycle.handle(.visible, for: 2)
        _ = lifecycle.handle(.hidden, for: 1)
        _ = lifecycle.handle(.wakeObserved, for: 1)
        #expect(lifecycle.handle(.visible, for: 1) == .begin)
        #expect(lifecycle.handle(.visible, for: 2) == .none)
        #expect(lifecycle.handle(.removed, for: 1) == .cancel)
        #expect(lifecycle.handle(.visible, for: 1) == .none)
    }

    @Test("A second sleep cancels a reveal armed by an interrupted wake")
    func interruptedWakeWaitsForFreshWake() {
        var lifecycle = RestDisplayLifecycle()
        _ = lifecycle.handle(.hidden, for: 1)
        _ = lifecycle.handle(.wakeObserved, for: 1)
        _ = lifecycle.handle(.hidden, for: 1)
        #expect(lifecycle.handle(.visible, for: 1) == .none)
        #expect(!lifecycle.isVisible(for: 1))
        #expect(lifecycle.handle(.wakeObserved, for: 1) == .arm)
        #expect(lifecycle.handle(.visible, for: 1) == .begin)
    }

    @Test("Visibility cannot consume a sleeping display before its wake event")
    func visibilityBeforeWakeDoesNotConsumeReveal() {
        var lifecycle = RestDisplayLifecycle()
        _ = lifecycle.handle(.hidden, for: 1)
        #expect(lifecycle.handle(.visible, for: 1) == .none)
        #expect(lifecycle.handle(.wakeObserved, for: 1) == .arm)
        #expect(lifecycle.handle(.visible, for: 1) == .begin)
    }
}
