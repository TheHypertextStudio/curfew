@testable import CurfewAtmosphere
import Foundation
import Testing

/// Band phase is the only motion in the sky: 0.05 bands per second while the
/// day is running, still while locked or under Reduce Motion, never jumping.
struct HorizonBandPhaseTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Bands advance 0.05 per second while the day is running")
    func advancesWhileRunning() {
        let phase = HorizonBandPhase(phase: 0.3, anchor: start, isRunning: true)
        #expect(abs(phase.value(at: start.addingTimeInterval(4)) - 0.5) < 1e-9)
        #expect(HorizonBandPhase.bandsPerSecond == 0.05)
    }

    @Test("Bands hold still when the day is not running")
    func holdsWhenStopped() {
        let phase = HorizonBandPhase(phase: 0.3, anchor: start, isRunning: false)
        #expect(abs(phase.value(at: start.addingTimeInterval(600)) - 0.3) < 1e-9)
    }

    @Test("Stopping holds the current value and resuming continues from it")
    func stopAndResumeWithoutJump() {
        var phase = HorizonBandPhase(phase: 0.1, anchor: start, isRunning: true)
        let stop = start.addingTimeInterval(6)
        phase = phase.updating(isRunning: false, at: stop)
        #expect(abs(phase.value(at: stop) - 0.4) < 1e-9)
        #expect(abs(phase.value(at: stop.addingTimeInterval(3600)) - 0.4) < 1e-9)
        let resume = stop.addingTimeInterval(3600)
        phase = phase.updating(isRunning: true, at: resume)
        #expect(abs(phase.value(at: resume) - 0.4) < 1e-9)
        #expect(abs(phase.value(at: resume.addingTimeInterval(2)) - 0.5) < 1e-9)
    }

    @Test("The value wraps to one band so long sessions keep shader precision")
    func wrapsToOneBand() {
        let phase = HorizonBandPhase(phase: 0.9, anchor: start, isRunning: true)
        let value = phase.value(at: start.addingTimeInterval(10))
        #expect(value >= 0)
        #expect(value < 1)
        #expect(abs(value - 0.4) < 1e-9)
    }

    @Test("Running is false under Reduce Motion even while the day runs")
    func reduceMotionHolds() {
        #expect(HorizonBandPhase.isRunning(dayIsRunning: true, reduceMotion: false))
        #expect(!HorizonBandPhase.isRunning(dayIsRunning: true, reduceMotion: true))
        #expect(!HorizonBandPhase.isRunning(dayIsRunning: false, reduceMotion: false))
    }
}
