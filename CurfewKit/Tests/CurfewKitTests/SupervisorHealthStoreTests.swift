@testable import CurfewKit
import Foundation
import Testing

struct SupervisorHealthStoreTests {
    @Test func failureSurvivesReloadAndHealthyCheckClearsIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("health.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let failed = SupervisorHealthRecord(lastCheckedAt: now, launchFailure: "App launch failed")
        try SupervisorHealthStore(recordURL: url).save(failed)
        let reloaded = SupervisorHealthStore(recordURL: url)
        #expect(try reloaded.load() == failed)
        try reloaded.save(SupervisorHealthRecord(lastCheckedAt: now.addingTimeInterval(5)))
        #expect(try reloaded.load()?.launchFailure == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func heartbeatExpiresAtNinetySeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let health = SupervisorHealthRecord(lastCheckedAt: now)
        #expect(health.isFresh(at: now.addingTimeInterval(89)))
        #expect(!health.isFresh(at: now.addingTimeInterval(90)))
        #expect(!health.isFresh(at: now.addingTimeInterval(-10)))
    }

    @Test func defaultStoresAreEphemeralAndCorruptionIsExplicit() throws {
        let first = SupervisorHealthStore()
        try first.save(SupervisorHealthRecord(lastCheckedAt: Date()))
        #expect(try first.load() != nil)
        #expect(try SupervisorHealthStore().load() == nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("broken".utf8).write(to: url)
        #expect(throws: (any Error).self) { try SupervisorHealthStore(recordURL: url).load() }
    }

    @Test func invalidTimeDoesNotReplaceExistingHealth() throws {
        let store = SupervisorHealthStore()
        let valid = SupervisorHealthRecord(lastCheckedAt: Date())
        try store.save(valid)
        #expect(throws: (any Error).self) {
            try store
                .save(SupervisorHealthRecord(lastCheckedAt: Date(timeIntervalSince1970: .infinity)))
        }
        #expect(try store.load() == valid)
    }

    @Test func liveStoreUsesCurrentFlavorDirectory() {
        #expect(SupervisorHealthStore.production().recordURL ==
            SharedPaths.applicationSupport.appendingPathComponent("supervisor-health.json"))
        #expect(CurfewFlavor.production.supervisorLabel != CurfewFlavor.development.supervisorLabel)
    }
}
