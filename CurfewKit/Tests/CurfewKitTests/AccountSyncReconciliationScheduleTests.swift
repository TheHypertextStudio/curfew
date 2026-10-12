@testable import CurfewKit
import Testing

struct AccountSyncReconciliationScheduleTests {
    @Test(
        "Explicit network restoration allows reconciliation without waiting on old failure backoff"
    )
    func restoredNetworkResumesImmediately() {
        var schedule = AccountSyncReconciliationSchedule()
        _ = schedule.beginDue(at: .zero)
        schedule.finish(.commands, at: .zero, succeeded: false)
        schedule.resume(at: .seconds(1))
        #expect(schedule.beginDue(at: .seconds(1)) == [.commands])
    }

    @Test("Idle reconciliation has a bounded full-day protected-read budget")
    func idleBudget() {
        var schedule = AccountSyncReconciliationSchedule()
        var counts: [AccountSyncReconciliationSchedule.Channel: Int] = [:]
        for second in 0 ..< 86400 {
            let time = Duration.seconds(second)
            for channel in schedule.beginDue(at: time) {
                counts[channel, default: 0] += 1
                schedule.finish(channel, at: time, succeeded: true)
            }
        }
        #expect(counts[.commands] == 1440)
        #expect(counts[.overrides] == 288)
        #expect(counts[.wake] == 288)
        #expect(counts[.peers] == 288)
        // Empty result scans are local, not protected requests.
        #expect(counts[.results] == 5760)
    }

    @Test("A hung wake read cannot block command fallback")
    func independentChannels() {
        var schedule = AccountSyncReconciliationSchedule()
        for channel in schedule.beginDue(at: .zero) where channel != .wake {
            schedule.finish(channel, at: .zero, succeeded: true)
        }
        let due = schedule.beginDue(at: .seconds(60))
        #expect(due.contains(.commands))
        #expect(!due.contains(.wake))
    }

    @Test("Hint bursts coalesce in-flight work and remember one trailing reconciliation")
    func boundedHints() {
        var schedule = AccountSyncReconciliationSchedule()
        _ = schedule.beginDue(at: .zero)
        for _ in 0 ..< 1000 {
            schedule.invalidate(at: .seconds(1))
        }
        #expect(schedule.beginDue(at: .seconds(2)).isEmpty)
        schedule.finish(.commands, at: .seconds(3), succeeded: true)
        #expect(schedule.beginDue(at: .seconds(9)).isEmpty)
        #expect(schedule.beginDue(at: .seconds(10)) == [.commands])
        schedule.finish(.commands, at: .seconds(10), succeeded: true)
        #expect(schedule.beginDue(at: .seconds(11)).isEmpty)
    }

    @Test("Repeated hints cannot defeat failure backoff")
    func failedHintBackoff() {
        var schedule = AccountSyncReconciliationSchedule()
        _ = schedule.beginDue(at: .zero)
        schedule.finish(.commands, at: .zero, succeeded: false)
        schedule.invalidate(at: .seconds(1))
        #expect(schedule.beginDue(at: .seconds(10)).isEmpty)
        #expect(schedule.beginDue(at: .seconds(15)) == [.commands])
        schedule.finish(.commands, at: .seconds(15), succeeded: false)
        schedule.invalidate(at: .seconds(16))
        #expect(schedule.beginDue(at: .seconds(44)).isEmpty)
        #expect(schedule.beginDue(at: .seconds(45)) == [.commands])
    }
}
