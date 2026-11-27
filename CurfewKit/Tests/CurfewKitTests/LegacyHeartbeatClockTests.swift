import CurfewKit
import Foundation
import Testing

struct LegacyHeartbeatClockTests {
    @Test func atomicReplacementWithRepeatedTimestampStartsFreshGrace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("heartbeat")
        let start = Date(timeIntervalSince1970: 10000)
        try replaceHeartbeat(at: url, timestamp: start)
        let firstIdentity = try FileManager.default.attributesOfItem(atPath: url.path)[
            .systemFileNumber
        ] as? NSNumber
        var clock = LegacyDaemonHeartbeatClock()
        #expect(clock.age(heartbeatURL: url, at: start) == 0)
        #expect(clock.age(heartbeatURL: url, at: start.addingTimeInterval(80)) == 80)

        try replaceHeartbeat(at: url, timestamp: start)
        let newIdentity = try FileManager.default.attributesOfItem(atPath: url.path)[
            .systemFileNumber
        ] as? NSNumber
        try #require(firstIdentity != nil && newIdentity != nil && firstIdentity != newIdentity)
        try #require(clock.age(heartbeatURL: url, at: start) == 0)
        #expect(clock.age(heartbeatURL: url, at: start.addingTimeInterval(91)) == 91)
    }

    @Test func unchangedLegacyFileRetainsElapsedAgeAcrossRollback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("heartbeat")
        let start = Date(timeIntervalSince1970: 10000)
        try replaceHeartbeat(at: url, timestamp: start)
        var clock = LegacyDaemonHeartbeatClock()
        #expect(clock.age(heartbeatURL: url, at: start.addingTimeInterval(80)) == 80)
        #expect(clock.age(heartbeatURL: url, at: start) == 80)
        #expect(clock.age(heartbeatURL: url, at: start.addingTimeInterval(11)) == 91)
    }

    @Test func missingLegacyFileRemainsHardStale() {
        var clock = LegacyDaemonHeartbeatClock()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(clock.age(heartbeatURL: url, at: Date(timeIntervalSince1970: 10000)) == .infinity)
    }

    private func replaceHeartbeat(at url: URL, timestamp: Date) throws {
        try Data().write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: timestamp],
            ofItemAtPath: url.path
        )
    }
}
