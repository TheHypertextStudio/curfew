@testable import CurfewAtmosphere
import CurfewKit
import Foundation
import Testing

@available(macOS 26.0, *)
struct RestAmbientSceneTests {
    @MainActor
    @Test("Missing occurrence keeps the chosen neutral night atmosphere without restriction status")
    func missingOccurrenceUsesNeutralNight() throws {
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
        #expect(scene.resolvedMoment == .night)
    }
}
