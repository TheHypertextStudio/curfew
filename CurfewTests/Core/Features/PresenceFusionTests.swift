@testable import Curfew
import Foundation
import Testing

/// The fusion rule, exhaustively.
///
/// Six combinations of (HID idle, camera signal) and six assertions — this is
/// the whole of ``PresenceFusion``, so covering the table covers the rule. The
/// two that matter most to the product are the pair at the bottom: idle plus
/// "camera saw someone" must never read as absent, and idle plus "no camera"
/// must never read as absent either.
struct PresenceFusionTests {
    @Test("Recent input reads as working whatever the camera says")
    func hidActivityWinsOutright() {
        for signal in PersonSignal.allCases {
            #expect(PresenceFusion.resolve(isHIDIdle: false, person: signal) == .working)
        }
    }

    @Test("Idle plus a visible person is present-but-idle, not absent")
    func idleWithPersonIsPresentButIdle() {
        #expect(
            PresenceFusion.resolve(isHIDIdle: true, person: .detected) == .presentButIdle
        )
    }

    @Test("Idle plus an empty frame is absent")
    func idleWithoutPersonIsAbsent() {
        #expect(PresenceFusion.resolve(isHIDIdle: true, person: .notDetected) == .absent)
    }

    @Test("Idle with no camera signal is unknown, never absent")
    func idleWithoutCameraIsUnknown() {
        let state = PresenceFusion.resolve(isHIDIdle: true, person: .unavailable)
        #expect(state == .unknown)
        // The distinction the whole feature rests on: "we cannot see" is not
        // "nobody is there". A default install, camera off, sits here.
        #expect(!state.isPersonKnownAbsent)
        #expect(!state.isPersonKnownPresent)
    }

    @Test("Only working and present-but-idle count as a known-present person")
    func knownPresenceIsNarrow() {
        #expect(PresenceState.working.isPersonKnownPresent)
        #expect(PresenceState.presentButIdle.isPersonKnownPresent)
        #expect(!PresenceState.absent.isPersonKnownPresent)
        #expect(!PresenceState.unknown.isPersonKnownPresent)
        #expect(PresenceState.absent.isPersonKnownAbsent)
        #expect(!PresenceState.unknown.isPersonKnownAbsent)
    }

    // MARK: - Observation freshness

    @Test("A reading inside the tolerance keeps its signal")
    func freshObservationKeepsSignal() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let observation = PersonObservation(
            signal: .detected,
            timestamp: now.addingTimeInterval(-5)
        )
        #expect(observation.isFresh(at: now, tolerance: 20))
        #expect(observation.signal(at: now, tolerance: 20) == .detected)
    }

    @Test("A reading past the tolerance decays to unavailable, not to absent")
    func staleObservationDecaysToUnavailable() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // A wedged capture session that last saw a person is the dangerous
        // case: if the reading did not decay, Curfew would keep reporting a
        // user who left an hour ago.
        let observation = PersonObservation(
            signal: .detected,
            timestamp: now.addingTimeInterval(-300)
        )
        #expect(!observation.isFresh(at: now, tolerance: 20))
        #expect(observation.signal(at: now, tolerance: 20) == .unavailable)
    }

    @Test("The never-observed sentinel is never fresh")
    func neverObservedIsNeverFresh() {
        let now = Date()
        #expect(!PersonObservation.never.isFresh(at: now, tolerance: 20))
        #expect(PersonObservation.never.signal(at: now, tolerance: 20) == .unavailable)
    }

    @Test("A reading timestamped in the future does not count as fresh")
    func futureObservationIsNotFresh() {
        // A backwards clock step must not extend a reading's life; treating a
        // future timestamp as fresh would do exactly that.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let observation = PersonObservation(
            signal: .detected,
            timestamp: now.addingTimeInterval(60)
        )
        #expect(!observation.isFresh(at: now, tolerance: 20))
    }
}
