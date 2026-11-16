@testable import CurfewAtmosphere
import Foundation
import Testing

/// The Horizon model is the prototype's `model()` ported to Swift. These tests pin
/// the path, the elevation curve, the weight ramps and the moon phase so the
/// shader and the CPU renderer are always fed the same frame.
struct HorizonModelTests {
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

    private let dayStart = Self.date(16, 7)
    private let curfew = Self.date(16, 18)
    private let unlock = Self.date(17, 7)

    private func frame(at now: Date, curfew: Date? = nil) -> HorizonFrame {
        HorizonMoment(
            now: now, dayStart: dayStart, curfew: curfew ?? self.curfew, nextUnlock: unlock
        ).frame
    }

    private func minutes(_ value: Double, from date: Date) -> Date {
        date.addingTimeInterval(value * 60)
    }

    @Test("The sun rises at the working day's start and meets the horizon at curfew")
    func pathEndpoints() {
        let rise = frame(at: dayStart)
        #expect(abs(rise.sun.x - 0.07) < 1e-9)
        #expect(abs(rise.sun.y - HorizonGeometry.horizon) < 1e-9)
        let set = frame(at: curfew)
        #expect(abs(set.sun.x - 0.93) < 1e-9)
        #expect(abs(set.sun.y - HorizonGeometry.horizon) < 1e-9)
    }

    @Test("The sun peaks halfway through the day at the quadratic's apex")
    func pathPeak() {
        let noon = frame(at: Self.date(16, 12, 30))
        #expect(abs(noon.sun.x - 0.5) < 1e-9)
        // 0.25 * 0.26 + 0.5 * 1.6 + 0.25 * 0.26
        #expect(abs(noon.sun.y - 0.93) < 1e-9)
        #expect(abs(noon.elevation - 1) < 1e-9)
    }

    @Test("A surface with a sidebar passes its own horizontal span")
    func customSpan() {
        let span = HorizonSpan(x0: 0.3, x1: 0.9)
        let noon = HorizonMoment(
            now: Self.date(16, 12, 30), dayStart: dayStart, curfew: curfew,
            nextUnlock: unlock, span: span
        ).frame
        #expect(abs(noon.sun.x - 0.6) < 1e-9)
        let set = HorizonMoment(
            now: curfew, dayStart: dayStart, curfew: curfew, nextUnlock: unlock, span: span
        ).frame
        #expect(abs(set.sun.x - 0.9) < 1e-9)
    }

    @Test("Elevation is continuous across curfew")
    func elevationContinuousAtCurfew() {
        let before = frame(at: curfew.addingTimeInterval(-1))
        let after = frame(at: curfew.addingTimeInterval(1))
        #expect(abs(before.elevation - after.elevation) < 1e-3)
        #expect(abs(frame(at: curfew).elevation) < 1e-9)
    }

    @Test("Elevation is continuous across the next unlock")
    func elevationContinuousAtUnlock() {
        let before = frame(at: unlock.addingTimeInterval(-1))
        let after = frame(at: unlock.addingTimeInterval(1))
        #expect(abs(before.elevation - after.elevation) < 1e-3)
        #expect(abs(frame(at: unlock).elevation) < 1e-9)
    }

    @Test("Night elevation sinks to -0.9 over 70 minutes and lifts over the last 35")
    func nightElevation() {
        #expect(abs(frame(at: minutes(35, from: curfew)).elevation + 0.45) < 1e-9)
        #expect(abs(frame(at: minutes(70, from: curfew)).elevation + 0.9) < 1e-9)
        #expect(abs(frame(at: Self.date(17, 1)).elevation + 0.9) < 1e-9)
        #expect(abs(frame(at: minutes(-35, from: unlock)).elevation + 0.9) < 1e-9)
        #expect(abs(frame(at: minutes(-17.5, from: unlock)).elevation + 0.45) < 1e-9)
    }

    @Test("The sun fades out 5 to 45 minutes after curfew while it keeps sinking")
    func sunWeightAfterCurfew() {
        #expect(frame(at: minutes(5, from: curfew)).sunWeight == 1)
        #expect(abs(frame(at: minutes(25, from: curfew)).sunWeight - 0.5) < 1e-9)
        #expect(frame(at: minutes(45, from: curfew)).sunWeight == 0)
        let sinking = frame(at: minutes(20, from: curfew))
        #expect(sinking.sun.y < HorizonGeometry.horizon)
        #expect(frame(at: Self.date(17, 1)).sunWeight == 0)
    }

    @Test("The sun fades in 40 to 5 minutes before unlock")
    func sunWeightBeforeUnlock() {
        #expect(frame(at: minutes(-40, from: unlock)).sunWeight == 0)
        #expect(abs(frame(at: minutes(-22.5, from: unlock)).sunWeight - 0.5) < 1e-9)
        #expect(frame(at: minutes(-5, from: unlock)).sunWeight == 1)
        #expect(frame(at: minutes(-10, from: unlock)).sun.y < HorizonGeometry.horizon)
    }

    @Test("The moon fades in 5 to 50 minutes after curfew and out 50 to 10 before unlock")
    func moonWeight() {
        #expect(frame(at: Self.date(16, 15)).moonWeight == 0)
        #expect(frame(at: minutes(5, from: curfew)).moonWeight == 0)
        #expect(abs(frame(at: minutes(27.5, from: curfew)).moonWeight - 0.5) < 1e-9)
        #expect(frame(at: minutes(50, from: curfew)).moonWeight == 1)
        #expect(frame(at: Self.date(17, 1)).moonWeight == 1)
        #expect(frame(at: minutes(-50, from: unlock)).moonWeight == 1)
        #expect(abs(frame(at: minutes(-30, from: unlock)).moonWeight - 0.5) < 1e-9)
        #expect(frame(at: minutes(-10, from: unlock)).moonWeight == 0)
    }

    @Test("The moon crosses the same path with progress across the night")
    func moonPath() {
        let midnight = frame(at: Self.date(17, 0, 30))
        #expect(abs(midnight.moon.x - 0.5) < 1e-9)
        #expect(abs(midnight.moon.y - 0.93) < 1e-9)
    }

    @Test("After unlock the next day rises from the start of the path")
    func nextMorning() {
        let morning = frame(at: minutes(30, from: unlock))
        #expect(morning.sunWeight == 1)
        #expect(morning.elevation > 0)
        #expect(morning.sun.x > 0.07)
        #expect(morning.sun.x < 0.2)
    }

    @Test("More time moves curfew later, so the sun steps back up the sky")
    func extensionRaisesTheSun() {
        let now = Self.date(16, 17, 40)
        let scheduled = frame(at: now)
        let extended = frame(at: now, curfew: minutes(15, from: curfew))
        #expect(extended.sun.y > scheduled.sun.y)
        #expect(extended.elevation > scheduled.elevation)
        #expect(extended.sun.x < scheduled.sun.x)
    }

    @Test("Moon phase is zero at the reference new moon and a half turn half a month later")
    func moonPhaseFromEpoch() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let epoch = try #require(utc.date(from: DateComponents(
            year: 2000, month: 1, day: 6, hour: 18, minute: 14
        )))
        let atEpoch = HorizonMoment.moonPhaseAngle(at: epoch)
        #expect(min(atEpoch, 2 * .pi - atEpoch) < 1e-3)
        let half = epoch.addingTimeInterval(HorizonMoment.synodicMonthDays / 2 * 86400)
        #expect(abs(HorizonMoment.moonPhaseAngle(at: half) - .pi) < 1e-3)
        let quarter = epoch.addingTimeInterval(HorizonMoment.synodicMonthDays / 4 * 86400)
        #expect(abs(HorizonMoment.moonPhaseAngle(at: quarter) - .pi / 2) < 1e-3)
    }

    @Test("Moon phase tracks a real new moon decades after the epoch")
    func moonPhaseKnownNewMoon() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // The new moon of the total solar eclipse, 2024-04-08 18:21 UTC. The mean
        // synodic month drifts from true lunations by under half a day.
        let eclipse = try #require(utc.date(from: DateComponents(
            year: 2024, month: 4, day: 8, hour: 18, minute: 21
        )))
        let angle = HorizonMoment.moonPhaseAngle(at: eclipse)
        #expect(min(angle, 2 * .pi - angle) < 0.25)
        #expect(HorizonMoment(
            now: eclipse, dayStart: dayStart, curfew: curfew, nextUnlock: unlock
        ).frame.moonPhase == angle)
    }

    @Test("A scheduled moment starts the day at the next unlock's clock time, a day earlier")
    func scheduledMoment() {
        let moment = HorizonMoment.scheduled(
            now: Self.date(16, 15), curfew: curfew, nextUnlock: unlock, calendar: Self.calendar
        )
        #expect(moment.dayStart == dayStart)
        #expect(moment.curfew == curfew)
        #expect(moment.nextUnlock == unlock)
        #expect(moment.span == .fullBleed)
    }

    @Test("Without a schedule the sky follows a 7 AM to 6 PM day")
    func unscheduledMoment() {
        let afternoon = HorizonMoment.unscheduled(now: Self.date(16, 15), calendar: Self.calendar)
        #expect(afternoon.dayStart == dayStart)
        #expect(afternoon.curfew == curfew)
        #expect(afternoon.nextUnlock == unlock)
        let small = HorizonMoment.unscheduled(now: Self.date(17, 3), calendar: Self.calendar)
        #expect(small.curfew == curfew)
        #expect(small.nextUnlock == unlock)
        #expect(small.frame.moonWeight == 1)
    }
}
