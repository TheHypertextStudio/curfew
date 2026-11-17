import CurfewAtmosphere
import Foundation
import Observation

/// The move into and out of the lock, as time. Pure, so it is tested without
/// windows.
///
/// Arriving is one move of about two seconds that starts the first time a lock
/// window is actually seen. A lock that begins under a screen saver or display
/// sleep plays its arrival when the screen is next seen instead of skipping it.
/// The sky cascades to night first, the clock settles in the centre, then the
/// words appear. Reduce Motion replaces the move with a short fade.
///
/// Leaving fades the whole scene to the desktop before the windows go.
struct LockSceneTimeline: Equatable {
    enum Stage: Equatable {
        case waitingToBeSeen, arriving, settled, leaving, gone
    }

    private(set) var arrivalStart: Date?
    private(set) var arrivalReducesMotion = false
    private(set) var leavingStart: Date?
    private(set) var leavingReducesMotion = false

    static func arrivalDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.3 : 2
    }

    static func leavingDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.3 : 1.2
    }

    /// A lock window was seen. Only the first sighting starts the arrival.
    mutating func seen(at date: Date, reduceMotion: Bool) {
        guard arrivalStart == nil else { return }
        arrivalStart = date
        arrivalReducesMotion = reduceMotion
    }

    /// The lock is already settled, as on a relaunch or a morning-only screen.
    mutating func settle(at date: Date) {
        guard arrivalStart == nil else { return }
        arrivalStart = date.addingTimeInterval(-Self.arrivalDuration(reduceMotion: false))
    }

    mutating func release(at date: Date, reduceMotion: Bool) {
        guard leavingStart == nil else { return }
        leavingStart = date
        leavingReducesMotion = reduceMotion
    }

    /// The lock came back while leaving: stay.
    mutating func relock() {
        leavingStart = nil
    }

    func stage(at date: Date) -> Stage {
        if let leavingStart {
            let done = date.timeIntervalSince(leavingStart)
                >= Self.leavingDuration(reduceMotion: leavingReducesMotion)
            return done ? .gone : .leaving
        }
        guard arrivalStart != nil else { return .waitingToBeSeen }
        return arrival(at: date) >= 1 ? .settled : .arriving
    }

    /// The arrival from 0 to 1; 0 until seen.
    func arrival(at date: Date) -> Double {
        guard let arrivalStart else { return 0 }
        let duration = Self.arrivalDuration(reduceMotion: arrivalReducesMotion)
        return min(max(date.timeIntervalSince(arrivalStart) / duration, 0), 1)
    }

    /// The scene's opacity while leaving, from 1 to 0.
    func presence(at date: Date) -> Double {
        guard let leavingStart else { return 1 }
        let duration = Self.leavingDuration(reduceMotion: leavingReducesMotion)
        return 1 - min(max(date.timeIntervalSince(leavingStart) / duration, 0), 1)
    }

    /// The sky's cascade to night, over the first 70% of the arrival.
    func sky(at date: Date) -> Double {
        guard !arrivalReducesMotion else { return arrivalStart == nil ? 0 : 1 }
        return Self.ease(segment(arrival(at: date), from: 0, to: 0.7))
    }

    /// The clock moving to the centre and growing, from 10% to 70%.
    func clock(at date: Date) -> Double {
        guard !arrivalReducesMotion else { return arrivalStart == nil ? 0 : 1 }
        return Self.ease(segment(arrival(at: date), from: 0.1, to: 0.7))
    }

    /// The headline and unlock line, over the last 40%.
    func words(at date: Date) -> Double {
        Self.ease(segment(arrival(at: date), from: 0.6, to: 1))
    }

    private func segment(_ value: Double, from lower: Double, to upper: Double) -> Double {
        min(max((value - lower) / (upper - lower), 0), 1)
    }

    /// The prototype's `cubic-bezier(.3,.7,.2,1)` is close to this ease out.
    private static func ease(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }
}

/// One lock scene shared by every display's window, so a display attached
/// mid-lock shows the same phase and content instead of restarting the
/// arrival. The coordinator owns it; each ``RestScreenView`` reads it.
@Observable
@MainActor
final class LockScene {
    private(set) var timeline = LockSceneTimeline()
    /// When this lock began. The sky's curfew never moves later than this,
    /// so a deadline that is recomputed every tick cannot freeze the scene.
    private(set) var began: Date?
    /// The sky the person was looking at as the lock began.
    private(set) var startingFrame: HorizonFrame?

    func begin(at date: Date, startingFrame: HorizonFrame) {
        guard began == nil else { return }
        began = date
        self.startingFrame = startingFrame
    }

    func seen(at date: Date, reduceMotion: Bool) {
        timeline.seen(at: date, reduceMotion: reduceMotion)
    }

    func settle(at date: Date) {
        timeline.settle(at: date)
    }

    func release(at date: Date, reduceMotion: Bool) {
        timeline.release(at: date, reduceMotion: reduceMotion)
    }

    func relock() {
        timeline.relock()
    }

    /// The curfew the lock's sky uses: the scheduled one, or when the lock
    /// began if that is earlier.
    func anchoredCurfew(_ curfew: Date) -> Date {
        guard let began else { return curfew }
        return min(curfew, began)
    }
}
