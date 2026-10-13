@testable import CurfewKit
import Foundation
import Testing

struct CurfewObservedStatusTests {
    @Test("A standby process cannot replace a live lock owner's observation")
    func standbyCannotClobberOwner() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-status-owner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurfewObservedStatusStore(
            fileURL: directory.appendingPathComponent("status.json")
        )
        let owner = CurfewObservedStatusPublisher(
            store: store, writerPID: 100, isWriterAlive: { _ in true }
        )
        let standby = CurfewObservedStatusPublisher(
            store: store, writerPID: 101, isWriterAlive: { _ in true }
        )
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let lock = CurfewEvaluation.locked(
            lockDate: now, unlockDate: now.addingTimeInterval(300)
        )

        try owner.publish(
            evaluation: lock, observedAt: now,
            enforcementRunning: true, ownsLockout: true
        )
        try standby.publish(
            evaluation: lock, observedAt: now.addingTimeInterval(1),
            enforcementRunning: true, ownsLockout: false
        )

        #expect(store.loadFresh(at: now.addingTimeInterval(1), isWriterAlive: { _ in true })?.phase
            == "locked")
    }

    @Test("Degraded protection cannot be reported as an enforced lock")
    func degradedLockIsUnavailable() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = CurfewObservedStatus(
            evaluation: .locked(lockDate: now, unlockDate: now.addingTimeInterval(300)),
            observedAt: now, enforcementRunning: true, ownsLockout: true,
            protectionHealthy: false
        )

        #expect(status.phase == "unknown")
        #expect(status.unavailableReason == "enforcement_degraded")
        #expect(status.unlockDate == nil)
    }

    @Test("Hours-based observations retain their configured countdown mode")
    func hoursModeIsObserved() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = CurfewObservedStatus(
            evaluation: .locked(
                lockDate: now, unlockDate: now.addingTimeInterval(300), trigger: .hours
            ),
            observedAt: now, enforcementRunning: true, ownsLockout: true,
            mode: .hours
        )

        #expect(status.mode == "hours")
        #expect(status.trigger == "hours")
    }

    @Test("Owned durable lock is reported from observed state")
    func ownedLockIsObserved() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let ends = started.addingTimeInterval(300)
        let status = CurfewObservedStatus(
            evaluation: .locked(lockDate: started, unlockDate: ends),
            observedAt: started.addingTimeInterval(10),
            enforcementRunning: true,
            ownsLockout: true
        )

        #expect(status.phase == "locked")
        #expect(status.unlockDate == ends)
        #expect(status.minutesRemaining == 0)
    }

    @Test("Disarmed and standby builds do not claim a predicted lock")
    func inactiveBuildDoesNotClaimLock() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let predicted = CurfewEvaluation.locked(
            lockDate: started,
            unlockDate: started.addingTimeInterval(300)
        )

        let disarmed = CurfewObservedStatus(
            evaluation: predicted,
            observedAt: started,
            enforcementRunning: false,
            ownsLockout: false
        )
        let standby = CurfewObservedStatus(
            evaluation: predicted,
            observedAt: started,
            enforcementRunning: true,
            ownsLockout: false
        )

        #expect(disarmed.phase == "unknown")
        #expect(standby.phase == "unknown")
        #expect(disarmed.unlockDate == nil)
        #expect(standby.unlockDate == nil)
        #expect(disarmed.minutesRemaining == nil)
        #expect(standby.minutesRemaining == nil)
        #expect(disarmed.availabilityDescription == "Curfew is off.")
        #expect(standby
            .availabilityDescription ==
            "Another Curfew app is enforcing; this build is standing by.")
    }

    @Test("Fresh observations survive a real file round trip and stale ones expire")
    func freshFileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-observed-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurfewObservedStatusStore(
            fileURL: directory.appendingPathComponent("status.json")
        )
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let status = CurfewObservedStatus(
            evaluation: .locked(
                lockDate: started,
                unlockDate: started.addingTimeInterval(300)
            ),
            observedAt: started,
            enforcementRunning: true,
            ownsLockout: true
        )

        try store.save(status)

        #expect(store.loadFresh(at: started.addingTimeInterval(30)) == status)
        #expect(store.loadFresh(at: started.addingTimeInterval(61)) == nil)
    }

    @Test("Publisher refreshes a changed phase immediately without writing every tick")
    func phaseChangePublishesImmediately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-status-publisher-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurfewObservedStatusStore(
            fileURL: directory.appendingPathComponent("status.json")
        )
        let publisher = CurfewObservedStatusPublisher(store: store)
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let lock = CurfewEvaluation.locked(
            lockDate: started,
            unlockDate: started.addingTimeInterval(300)
        )

        try publisher.publish(
            evaluation: lock,
            observedAt: started,
            enforcementRunning: true,
            ownsLockout: true
        )
        try publisher.publish(
            evaluation: lock,
            observedAt: started.addingTimeInterval(1),
            enforcementRunning: true,
            ownsLockout: true
        )
        #expect(store.loadFresh(at: started.addingTimeInterval(1))?.observedAt == started)

        try publisher.publish(
            evaluation: lock,
            observedAt: started.addingTimeInterval(2),
            enforcementRunning: false,
            ownsLockout: false
        )
        #expect(store.loadFresh(at: started.addingTimeInterval(2))?.phase == "unknown")
        #expect(store.loadFresh(at: started.addingTimeInterval(2))?.observedAt
            == started.addingTimeInterval(2))
    }
}
