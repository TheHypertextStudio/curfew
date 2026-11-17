@testable import CurfewAtmosphere
import Foundation
import Testing

/// The lock is the same scene after dark: night from the moment it arrives,
/// the model's own warming toward unlock, and a blend for the arrival move.
struct LockSceneSkyTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        ))!
    }

    private func moment(at now: Date, unlock: Date = Self.date(17, 7)) -> HorizonMoment {
        HorizonMoment(
            now: now,
            dayStart: Self.date(16, 7),
            curfew: Self.date(16, 18),
            nextUnlock: unlock
        )
    }

    @Test("The lock is full night at the moment curfew arrives")
    func nightAtCurfew() {
        let frame = LockSceneSky.frame(for: moment(at: Self.date(16, 18)))
        #expect(abs(frame.elevation - -0.9) < 1e-9)
        #expect(frame.sunWeight == 0)
        #expect(abs(frame.moonWeight - 1) < 1e-9)
    }

    @Test("Deep in the night the lock is the model's own frame")
    func deepNightMatchesModel() {
        let night = moment(at: Self.date(17, 1))
        #expect(LockSceneSky.frame(for: night) == night.frame)
    }

    @Test("Toward unlock the sky warms exactly as the model does")
    func leadInWarms() {
        let leadIn = moment(at: Self.date(17, 6, 50))
        let frame = LockSceneSky.frame(for: leadIn)
        #expect(frame == leadIn.frame)
        #expect(frame.elevation > -0.9)
    }

    @Test("A short night never borrows the morning ramp")
    func shortNightStaysBeforeMorning() {
        let short = moment(at: Self.date(16, 18), unlock: Self.date(16, 19, 30))
        let scene = LockSceneSky.sceneTime(for: short)
        #expect(scene <= Self.date(16, 18, 45))
        #expect(scene >= Self.date(16, 18))
    }

    @Test("The moon keeps tonight's real phase")
    func moonPhaseIsReal() {
        let now = Self.date(16, 18)
        #expect(LockSceneSky.frame(for: moment(at: now)).moonPhase
            == HorizonMoment.moonPhaseAngle(at: now))
    }

    @Test("The arrival blend runs from the sky in view to the lock's night")
    func blendEnds() {
        let before = moment(at: Self.date(16, 18)).frame
        let after = LockSceneSky.frame(for: moment(at: Self.date(16, 18)))
        #expect(LockSceneSky.blend(before, after, amount: 0) == before)
        #expect(LockSceneSky.blend(before, after, amount: 1) == after)
        let middle = LockSceneSky.blend(before, after, amount: 0.5)
        #expect(abs(middle.elevation - (before.elevation + after.elevation) / 2) < 1e-9)
        #expect(LockSceneSky.blend(before, after, amount: 4) == after)
    }
}
