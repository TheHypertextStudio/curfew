@testable import Curfew
import Foundation
import Testing

/// Hold to confirm: the fill tracks the hold, confirmation fires once at the
/// configured duration, and letting go early cancels.
struct HoldToConfirmTimerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Progress fills while held and confirms once at the duration")
    func confirmsAtDuration() {
        var timer = HoldToConfirmTimer(duration: 1.1)
        #expect(!timer.isHolding)
        #expect(timer.progress(at: start) == 0)
        timer.press(at: start)
        #expect(timer.isHolding)
        #expect(abs(timer.progress(at: start.addingTimeInterval(0.55)) - 0.5) < 1e-6)
        #expect(timer.update(at: start.addingTimeInterval(0.55)) == false)
        #expect(timer.update(at: start.addingTimeInterval(1.1)) == true)
        #expect(timer.isConfirmed)
        #expect(timer.progress(at: start.addingTimeInterval(1.1)) == 1)
        // Confirmation fires once however long the hold continues.
        #expect(timer.update(at: start.addingTimeInterval(2)) == false)
    }

    @Test("Letting go before the duration cancels and empties the fill")
    func releaseCancels() {
        var timer = HoldToConfirmTimer(duration: 1.1)
        timer.press(at: start)
        timer.release(at: start.addingTimeInterval(0.8))
        #expect(!timer.isHolding)
        #expect(!timer.isConfirmed)
        #expect(timer.progress(at: start.addingTimeInterval(0.9)) == 0)
        #expect(timer.update(at: start.addingTimeInterval(1.5)) == false)
    }

    @Test("A second press after release starts a fresh hold")
    func pressRestarts() {
        var timer = HoldToConfirmTimer(duration: 2)
        timer.press(at: start)
        timer.release(at: start.addingTimeInterval(1))
        let again = start.addingTimeInterval(5)
        timer.press(at: again)
        #expect(abs(timer.progress(at: again.addingTimeInterval(1)) - 0.5) < 1e-6)
        // Repeated key-down events do not restart a hold in progress.
        timer.press(at: again.addingTimeInterval(1))
        #expect(abs(timer.progress(at: again.addingTimeInterval(1)) - 0.5) < 1e-6)
    }

    @Test("Accessibility confirms immediately, without a hold")
    func accessibilityConfirm() {
        var timer = HoldToConfirmTimer(duration: 1.1)
        #expect(timer.confirmImmediately() == true)
        #expect(timer.isConfirmed)
        #expect(timer.confirmImmediately() == false)
        timer.reset()
        #expect(!timer.isConfirmed)
        #expect(timer.progress(at: start) == 0)
    }

    @Test("Durations are kept positive")
    func positiveDuration() {
        var timer = HoldToConfirmTimer(duration: 0)
        timer.press(at: start)
        #expect(timer.update(at: start.addingTimeInterval(0.2)) == true)
    }
}
