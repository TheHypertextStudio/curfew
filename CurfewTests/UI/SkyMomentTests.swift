// Behavior tests for the living-sky model (`SkyMoment`).
//
// `SkyMoment.resolve` is a pure function (clock + curfew window → sky), so the
// whole atmosphere mapping is verified here without touching SwiftUI: the
// time-of-day fallback curve, the pre-lock descent + ember proximity ramp, and
// the night arc that darkens at the midpoint and lifts toward dawn.

@testable import Curfew
import CurfewKit
import Foundation
import Testing

private func date(hour: Int, minute: Int = 0) -> Date {
    var components = Calendar.current.dateComponents(
        [.year, .month, .day],
        from: Date(timeIntervalSince1970: 1_700_000_000)
    )
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components) ?? Date()
}

struct SkyMomentTimeOfDayTests {
    @Test("With no curfew window the sky follows the clock")
    func clockCurve() {
        let deepNight = SkyMoment.resolve(
            now: date(hour: 1), lockDate: nil, unlockDate: nil, phase: .dayOff
        )
        #expect(deepNight.light < 0.05)

        let midday = SkyMoment.resolve(
            now: date(hour: 13), lockDate: nil, unlockDate: nil, phase: .dayOff
        )
        #expect(midday.light > 0.95)

        let dawn = SkyMoment.resolve(
            now: date(hour: 7), lockDate: nil, unlockDate: nil, phase: .dayOff
        )
        #expect(abs(dawn.light - 0.5) < 0.05)
        #expect(dawn.rising)

        let dusk = SkyMoment.resolve(
            now: date(hour: 19), lockDate: nil, unlockDate: nil, phase: .dayOff
        )
        #expect(abs(dusk.light - 0.5) < 0.05)
        #expect(!dusk.rising)
    }
}

struct SkyMomentApproachingTests {
    @Test("The sky descends toward the horizon as the lock time nears")
    func descent() {
        let now = date(hour: 12)

        let farOut = SkyMoment.resolve(
            now: now,
            lockDate: now.addingTimeInterval(6 * 3600),
            unlockDate: nil,
            phase: .working
        )
        #expect(farOut.light > 0.9)
        #expect(farOut.proximity == 0)

        let atLock = SkyMoment.resolve(
            now: now,
            lockDate: now,
            unlockDate: nil,
            phase: .warning
        )
        #expect(abs(atLock.light - 0.44) < 0.02)
        #expect(atLock.proximity == 1)
        #expect(!atLock.rising)
    }

    @Test("Ember proximity ramps over the final 90 minutes")
    func proximityRamp() {
        let now = date(hour: 20)
        let halfway = SkyMoment.resolve(
            now: now,
            lockDate: now.addingTimeInterval(45 * 60),
            unlockDate: nil,
            phase: .warning
        )
        #expect(abs(halfway.proximity - 0.5) < 0.02)

        let stillFar = SkyMoment.resolve(
            now: now,
            lockDate: now.addingTimeInterval(120 * 60),
            unlockDate: nil,
            phase: .working
        )
        #expect(stillFar.proximity == 0)
    }
}

struct SkyMomentLockedTests {
    @Test("Night is darkest at the midpoint and lifts toward unlock")
    func nightArc() {
        let lock = date(hour: 22)
        let unlock = lock.addingTimeInterval(8 * 3600)

        let justLocked = SkyMoment.resolve(
            now: lock, lockDate: lock, unlockDate: unlock, phase: .locked
        )
        #expect(abs(justLocked.light - 0.40) < 0.02)
        #expect(!justLocked.rising)

        let midnight = SkyMoment.resolve(
            now: lock.addingTimeInterval(4 * 3600),
            lockDate: lock,
            unlockDate: unlock,
            phase: .locked
        )
        #expect(midnight.light < 0.1)

        let preDawn = SkyMoment.resolve(
            now: lock.addingTimeInterval(6 * 3600),
            lockDate: lock,
            unlockDate: unlock,
            phase: .locked
        )
        #expect(preDawn.rising)
        #expect(preDawn.light > midnight.light)
    }

    @Test("Locked with no window falls back to the night preset")
    func lockedWithoutWindow() {
        let moment = SkyMoment.resolve(
            now: date(hour: 23), lockDate: nil, unlockDate: nil, phase: .locked
        )
        #expect(moment == .night)
    }
}
