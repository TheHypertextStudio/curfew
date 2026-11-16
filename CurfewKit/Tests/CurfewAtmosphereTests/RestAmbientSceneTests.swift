@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

struct RestAmbientSceneTests {
    @MainActor
    @Test("Missing occurrence rests in the middle of a night without restriction status")
    func missingOccurrenceUsesRestingNight() throws {
        guard #available(macOS 26.0, *) else {
            Issue.record("The shared renderer requires the supported macOS 26 test host")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let midday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 22, hour: 13
        )))
        let snapshot = RestSceneSnapshot(
            version: 1, expiresAt: midday.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(), lockDate: nil, unlockDate: nil
        )
        let scene = RestAmbientScene(snapshot: snapshot, date: midday)
        #expect(snapshot.resolve(at: midday, timeZone: .current).phase == .allDay)
        #expect(scene.resolvedFrame == HorizonMoment.restingNight(at: midday).frame)
        #expect(scene.resolvedFrame.moonWeight == 1)
        #expect(scene.resolvedFrame.sunWeight == 0)
        #expect(!scene.bandsDrift)
    }

    @MainActor
    @Test("A scheduled night feeds the Horizon model from the session's curfew and unlock")
    func scheduledNightUsesSessionTimes() {
        guard #available(macOS 26.0, *) else {
            Issue.record("The shared renderer requires the supported macOS 26 test host")
            return
        }
        let lock = Date(timeIntervalSince1970: 1_800_000_000)
        let unlock = lock.addingTimeInterval(13 * 3600)
        let now = lock.addingTimeInterval(3 * 3600)
        let snapshot = RestSceneSnapshot(
            version: 1, expiresAt: now.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(), lockDate: lock, unlockDate: unlock
        )
        let scene = RestAmbientScene(snapshot: snapshot, date: now)
        #expect(scene.resolvedFrame == HorizonMoment.scheduled(
            now: now, curfew: lock, nextUnlock: unlock
        ).frame)
        #expect(scene.resolvedFrame.elevation == -0.9)
        #expect(!scene.bandsDrift)
    }
}
