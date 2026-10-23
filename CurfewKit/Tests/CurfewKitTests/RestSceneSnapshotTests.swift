@testable import CurfewKit
import Foundation
import Testing

/// Test-only API proposal; no implementation or behavioral RED is claimed.
/// See .superpowers/sdd/rest-experience-features-plan/task-2-contract-report.md.
struct RestSceneSnapshotTests {
    private let lock = Date(timeIntervalSince1970: 1_792_616_400)
    private var unlock: Date {
        lock.addingTimeInterval(8 * 3600)
    }

    private var zone: TimeZone {
        TimeZone(secondsFromGMT: -7 * 3600)!
    }

    private func snapshot(
        version: Int = 1,
        lead: Int = 30,
        lockDate: Date? = nil,
        unlockDate: Date? = nil
    ) -> RestSceneSnapshot {
        RestSceneSnapshot(
            version: version,
            expiresAt: unlock.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(sunriseLeadMinutes: lead),
            lockDate: lockDate ?? lock,
            unlockDate: unlockDate ?? unlock
        )
    }

    @Test("Missing, expired and unsupported occurrence context is neutral all-day")
    func neutralFallbacks() {
        let absent = RestSceneSnapshot(
            version: 1, expiresAt: unlock, appearance: RestAppearancePreferences(),
            lockDate: nil, unlockDate: nil
        )
        #expect(absent.resolve(at: lock, timeZone: zone).phase == .allDay)
        #expect(snapshot(version: 2).resolve(at: lock, timeZone: zone).phase == .allDay)
        #expect(snapshot().resolve(at: unlock.addingTimeInterval(3600), timeZone: zone)
            .phase == .allDay)
        #expect(snapshot().resolve(at: unlock.addingTimeInterval(3601), timeZone: zone)
            .phase == .allDay)
    }

    @Test("Partial, reversed, equal and nonfinite occurrence timestamps are neutral")
    func malformedOccurrence() {
        let pairs: [(Date?, Date?)] = [
            (lock, nil), (nil, unlock), (unlock, lock), (lock, lock),
            (Date(timeIntervalSince1970: .infinity), unlock),
            (lock, Date(timeIntervalSince1970: .nan))
        ]
        for (start, end) in pairs {
            let value = RestSceneSnapshot(
                version: 1, expiresAt: unlock.addingTimeInterval(3600),
                appearance: RestAppearancePreferences(), lockDate: start, unlockDate: end
            )
            let frame = value.resolve(at: lock, timeZone: zone)
            #expect(frame.phase == .allDay)
            #expect(frame.sunriseProgress == 0)
        }
    }

    @Test(
        "Night and Sunrise use the exact default and custom lead boundaries",
        arguments: [5, 30, 60]
    )
    func leadBoundaries(lead: Int) {
        let value = snapshot(lead: lead)
        let start = unlock.addingTimeInterval(-Double(lead) * 60)
        #expect(value.resolve(at: lock.addingTimeInterval(-1), timeZone: zone).phase == .allDay)
        #expect(value.resolve(at: lock, timeZone: zone).phase == .night)
        #expect(value.resolve(at: start.addingTimeInterval(-0.001), timeZone: zone).phase == .night)
        let first = value.resolve(at: start, timeZone: zone)
        #expect(first.phase == .sunrise)
        #expect(first.sunriseProgress == 0)
        let middle = value.resolve(at: start.addingTimeInterval(Double(lead) * 30), timeZone: zone)
        #expect(middle.phase == .sunrise)
        #expect(abs(middle.sunriseProgress - 0.5) < 0.000_001)
        #expect(value.resolve(at: unlock.addingTimeInterval(-0.001), timeZone: zone)
            .phase == .sunrise)
        #expect(value.resolve(at: unlock, timeZone: zone).phase == .morning)
        #expect(value.resolve(at: unlock, timeZone: zone).sunriseProgress == 1)
        #expect(value.resolve(at: unlock.addingTimeInterval(1), timeZone: zone).phase == .morning)
    }

    @Test(
        "The migration default uses a thirty-minute visual lead even with automatic wake disabled"
    )
    func defaultLead() {
        let value = snapshot()
        #expect(!value.appearance.sunriseWakeEnabled)
        #expect(value.resolve(at: unlock.addingTimeInterval(-1800), timeZone: zone)
            .phase == .sunrise)
        #expect(value.resolve(at: unlock.addingTimeInterval(-1801), timeZone: zone).phase == .night)
    }

    @Test("Clock jumps recompute from the supplied timestamp without retained progression")
    func clockJumps() {
        let value = snapshot()
        let night = lock.addingTimeInterval(3600)
        let sunrise = unlock.addingTimeInterval(-900)
        let morning = unlock.addingTimeInterval(1)
        let expectedNight = value.resolve(at: night, timeZone: zone)
        let expectedSunrise = value.resolve(at: sunrise, timeZone: zone)
        #expect(value.resolve(at: morning, timeZone: zone).phase == .morning)
        #expect(value.resolve(at: sunrise, timeZone: zone) == expectedSunrise)
        #expect(value.resolve(at: night, timeZone: zone) == expectedNight)
        #expect(value.resolve(at: sunrise, timeZone: zone) == expectedSunrise)
    }

    @Test("An occurrence crosses local midnight without switching to another day")
    func midnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: 22,
            hour: 23
        )))
        let end = start.addingTimeInterval(8 * 3600)
        let value = RestSceneSnapshot(
            version: 1, expiresAt: end.addingTimeInterval(3600),
            appearance: RestAppearancePreferences(), lockDate: start, unlockDate: end
        )
        for delta in [3599.0, 3600, 3601] {
            #expect(value.resolve(at: start.addingTimeInterval(delta), timeZone: zone)
                .phase == .night)
        }
        #expect(value.resolve(at: end, timeZone: zone).phase == .morning)
    }

    @Test("App and companion Codable inputs resolve identically at the same absolute instant")
    func companionParity() throws {
        let app = snapshot()
        let data = try JSONEncoder().encode(app)
        let companion = try JSONDecoder().decode(RestSceneSnapshot.self, from: data)
        for instant in [
            lock.addingTimeInterval(-1),
            lock,
            unlock.addingTimeInterval(-1800),
            unlock.addingTimeInterval(-900),
            unlock
        ] {
            #expect(app.resolve(at: instant, timeZone: zone) == companion.resolve(
                at: instant,
                timeZone: zone
            ))
        }
    }
}
