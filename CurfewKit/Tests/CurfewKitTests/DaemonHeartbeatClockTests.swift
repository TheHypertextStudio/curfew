import CurfewKit
import Foundation
import Testing

struct DaemonHeartbeatClockTests {
    private let start = Date(timeIntervalSince1970: 10000)

    private func record() -> LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: start,
            scheduledUnlockAt: start.addingTimeInterval(8 * 3600),
            kind: .scheduledTime
        )
    }

    @Test func clockRollbackPreservesRemainingHeartbeatTimeout() throws {
        var machine = PrivilegedEnforcementStateMachine(startedAt: start)
        try machine.arm(record(), now: start)
        #expect(machine.evaluate(now: start.addingTimeInterval(40)) == .none)
        let corrected = start.addingTimeInterval(-3600)
        #expect(machine.evaluate(now: corrected) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(50)) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(51)) == .shutdown)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(60)) == .none)
    }

    @Test func repeatedRollbacksCannotRefillHeartbeatTimeout() throws {
        var machine = PrivilegedEnforcementStateMachine(startedAt: start)
        try machine.arm(record(), now: start)
        #expect(machine.evaluate(now: start.addingTimeInterval(30)) == .none)
        let first = start.addingTimeInterval(-3600)
        #expect(machine.evaluate(now: first) == .none)
        #expect(machine.evaluate(now: first.addingTimeInterval(30)) == .none)
        let second = first.addingTimeInterval(-3600)
        #expect(machine.evaluate(now: second) == .none)
        #expect(machine.evaluate(now: second.addingTimeInterval(30)) == .none)
        #expect(machine.evaluate(now: second.addingTimeInterval(31)) == .shutdown)
    }

    @Test func futurePersistedHeartbeatGetsBoundedGraceAfterRestart() {
        let corrected = start.addingTimeInterval(-3600)
        let status = PrivilegedDaemonStatus(
            activeRecord: record(), lastHeartbeatAt: start, shutdownIssued: false
        )
        var machine = PrivilegedEnforcementStateMachine(status: status, startedAt: corrected)
        #expect(machine.evaluate(now: corrected) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(90)) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(91)) == .shutdown)
    }

    @Test func restartWithoutHeartbeatRetainsRemainingStartupGraceOnRollback() {
        var machine = PrivilegedEnforcementStateMachine(record: record(), startedAt: start)
        #expect(machine.evaluate(now: start.addingTimeInterval(40)) == .none)
        let corrected = start.addingTimeInterval(-3600)
        #expect(machine.evaluate(now: corrected) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(50)) == .none)
        #expect(machine.evaluate(now: corrected.addingTimeInterval(51)) == .shutdown)
    }

    @Test func freshHeartbeatAfterRollbackReceivesNormalTimeout() throws {
        let deadline = record()
        var machine = PrivilegedEnforcementStateMachine(startedAt: start)
        try machine.arm(deadline, now: start)
        #expect(machine.evaluate(now: start.addingTimeInterval(40)) == .none)
        let corrected = start.addingTimeInterval(-3600)
        #expect(machine.evaluate(now: corrected) == .none)
        let heartbeat = corrected.addingTimeInterval(40)
        try machine.heartbeat(lockoutID: deadline.lockoutID, now: heartbeat)
        #expect(machine.evaluate(now: heartbeat.addingTimeInterval(89)) == .none)
        #expect(machine.evaluate(now: heartbeat.addingTimeInterval(91)) == .shutdown)
    }
}
