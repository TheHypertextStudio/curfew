@testable import Curfew
import CurfewAtmosphere
import Foundation
import Testing

/// The app feeds the Horizon model from the real schedule. The scene must stay
/// continuous when the evaluation hands over from one night's window to the
/// next day's.
struct HorizonSkyModelTests {
    private let lock = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The rest scene is continuous across the scheduled unlock")
    func restContinuousAtUnlock() {
        let unlock = lock.addingTimeInterval(13 * 3600)
        let night = RestSessionContext(lockDate: lock, unlockDate: unlock)
        let nextDay = RestSessionContext(
            lockDate: unlock.addingTimeInterval(11 * 3600),
            unlockDate: unlock.addingTimeInterval(24 * 3600)
        )
        let before = RestPresentationSnapshot.sky(
            now: unlock.addingTimeInterval(-1),
            session: night
        )
        let after = RestPresentationSnapshot.sky(
            now: unlock.addingTimeInterval(1),
            session: nextDay
        )
        #expect(abs(before.elevation - after.elevation) < 1e-3)
        #expect(abs(before.sun.x - after.sun.x) < 1e-3)
        #expect(abs(before.sun.y - after.sun.y) < 1e-3)
        #expect(abs(before.sunWeight - after.sunWeight) < 1e-3)
    }

    @Test("A session without a schedule rests in the night")
    func restWithoutSchedule() {
        let sky = RestPresentationSnapshot.sky(
            now: lock, session: RestSessionContext(lockDate: nil, unlockDate: nil)
        )
        #expect(sky == HorizonMoment.restingNight(at: lock).frame)
    }

    @Test("Locked at 9:41 PM the sun has set and the moon is up")
    func lockedEvening() {
        let unlock = lock.addingTimeInterval(13 * 3600)
        let sky = RestPresentationSnapshot.sky(
            now: lock.addingTimeInterval(3 * 3600 + 41 * 60),
            session: RestSessionContext(lockDate: lock, unlockDate: unlock)
        )
        #expect(sky.sunWeight == 0)
        #expect(sky.moonWeight == 1)
        #expect(sky.elevation == -0.9)
    }
}
