@testable import Curfew
import Foundation
import Testing

/// Coverage for the daemon's observation records.
///
/// This logic used to be a private function inside `main.swift`, where no test
/// could reach it, and it shipped with break-glass recording its start and
/// never its end. Every dimension here is now asserted in *both* directions,
/// because a one-directional record is exactly the defect that hid there.
struct DaemonAuditObserverTests {
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)

    private var window: LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStart,
            scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
            kind: .scheduledTime
        )
    }

    private func makeObserver() -> (observer: DaemonAuditObserver, writer: RecordingAuditWriter) {
        let writer = RecordingAuditWriter()
        return (DaemonAuditObserver(auditLog: AuditLog(stream: .daemon, writer: writer)), writer)
    }

    private func observation(
        at now: Date,
        heartbeatAge: TimeInterval = 0,
        hasWork: Bool = false,
        breakGlass: BreakGlassRelease? = nil,
        deadline: LockoutDeadlineRecord? = nil,
        fromUserFile: Bool = true
    ) -> DaemonAuditObserver.Observation {
        DaemonAuditObserver.Observation(
            now: now,
            deadline: deadline ?? window,
            deadlineCameFromUserFile: fromUserFile,
            heartbeatAge: heartbeatAge,
            heartbeatTimeout: 90,
            hasActiveProtectedWork: hasWork,
            breakGlass: breakGlass
        )
    }

    private func release(issuedAt: Date) -> BreakGlassRelease {
        BreakGlassRelease(
            issuedAt: issuedAt,
            reason: "laptop wedged mid-deploy",
            issuedBy: "curfew-ctl"
        )
    }

    private func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    // MARK: - Break-glass, both directions

    @Test("A release arriving is recorded with its identifier")
    func breakGlassArrivalIsRecorded() throws {
        let (observer, writer) = makeObserver()
        let now = lockoutStart.addingTimeInterval(300)
        let active = release(issuedAt: now)

        observer.record(observation(at: now, breakGlass: active))

        let record = try #require(writer.first(.breakGlassObserved))
        #expect(detailString(record, "releaseId") == active.id.uuidString)
        #expect(record.detail["issuedAt"] != nil)
    }

    @Test("A release expiring or being revoked is recorded, not silently dropped")
    func breakGlassEndingIsRecorded() throws {
        let (observer, writer) = makeObserver()
        let now = lockoutStart.addingTimeInterval(300)
        let active = release(issuedAt: now)

        observer.record(observation(at: now, breakGlass: active))
        // The release lifts. This is the moment enforcement re-arms, and it is
        // the fact an auditor needs in order to bound the window it covered.
        observer.record(observation(at: now.addingTimeInterval(15), breakGlass: nil))

        #expect(writer.records(ofType: .breakGlassObserved).count == 1)
        let cleared = try #require(writer.first(.breakGlassCleared))
        #expect(cleared.from == active.id.uuidString)
        #expect(cleared.to == "none")
        #expect(cleared.actor.token == "daemon")
    }

    @Test("A second release after one lifts is recorded as its own arrival")
    func breakGlassKeyResetsAfterClearing() {
        let (observer, writer) = makeObserver()
        var now = lockoutStart.addingTimeInterval(300)

        observer.record(observation(at: now, breakGlass: release(issuedAt: now)))
        now = now.addingTimeInterval(15)
        observer.record(observation(at: now, breakGlass: nil))
        now = now.addingTimeInterval(15)
        // A dedup key that never reset would swallow this one.
        observer.record(observation(at: now, breakGlass: release(issuedAt: now)))

        #expect(writer.records(ofType: .breakGlassObserved).count == 2)
        #expect(writer.records(ofType: .breakGlassCleared).count == 1)
    }

    @Test("A release held across many ticks is recorded once")
    func breakGlassIsNotRepeated() {
        let (observer, writer) = makeObserver()
        var now = lockoutStart.addingTimeInterval(300)
        let active = release(issuedAt: now)

        for _ in 0 ..< 6 {
            observer.record(observation(at: now, breakGlass: active))
            now = now.addingTimeInterval(15)
        }

        #expect(writer.records(ofType: .breakGlassObserved).count == 1)
    }

    // MARK: - The neighbours it must stay symmetric with

    @Test("Protected work is recorded arriving and clearing")
    func protectedWorkIsRecordedBothWays() {
        let (observer, writer) = makeObserver()
        let now = lockoutStart.addingTimeInterval(300)

        observer.record(observation(at: now, hasWork: true))
        observer.record(observation(at: now.addingTimeInterval(15), hasWork: false))

        #expect(writer.records(ofType: .protectedWorkActive).count == 1)
        #expect(writer.records(ofType: .protectedWorkCleared).count == 1)
    }

    @Test("The heartbeat is recorded going stale and recovering")
    func heartbeatIsRecordedBothWays() throws {
        let (observer, writer) = makeObserver()
        let now = lockoutStart.addingTimeInterval(300)

        observer.record(observation(at: now, heartbeatAge: 600))
        observer.record(observation(at: now.addingTimeInterval(15), heartbeatAge: 0))

        #expect(writer.records(ofType: .daemonHeartbeatStale).count == 1)
        #expect(writer.records(ofType: .daemonHeartbeatRecovered).count == 1)
        let stale = try #require(writer.first(.daemonHeartbeatStale))
        #expect(stale.detail["ageSeconds"] == .int(600))
    }

    @Test("A missing heartbeat file records an integer age, not a null")
    func missingHeartbeatRecordsSentinelAge() throws {
        let (observer, writer) = makeObserver()

        observer.record(observation(
            at: lockoutStart.addingTimeInterval(300),
            heartbeatAge: .infinity
        ))

        let record = try #require(writer.first(.daemonHeartbeatStale))
        #expect(record.detail["ageSeconds"] == .int(-1))
        #expect(record.detail["heartbeatPresent"] == .bool(false))
    }

    // MARK: - Deadline

    @Test("A deadline read from the root shadow is recorded as such")
    func shadowSourcedDeadlineIsRecorded() throws {
        let (observer, writer) = makeObserver()

        observer.record(
            observation(at: lockoutStart.addingTimeInterval(300), fromUserFile: false)
        )

        let record = try #require(writer.first(.daemonDeadlineObserved))
        #expect(detailString(record, "source") == "shadow")
        #expect(detailString(record, "kind") == "scheduled_time")
    }

    @Test("The same window across many ticks is recorded once")
    func deadlineIsNotRepeated() {
        let (observer, writer) = makeObserver()
        var now = lockoutStart.addingTimeInterval(300)

        for _ in 0 ..< 6 {
            observer.record(observation(at: now))
            now = now.addingTimeInterval(15)
        }

        #expect(writer.records(ofType: .daemonDeadlineObserved).count == 1)
    }
}
