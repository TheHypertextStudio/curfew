@testable import Curfew
import Foundation
import Testing

/// Minimal stand-in for the machine. `DaemonEnforcementRuntimeTests` has its
/// own copy scoped to that file; this one exists so the two suites can move
/// independently — these tests assert on what was *recorded*, that one asserts
/// on what was *done*, and coupling them through a shared spy would make a
/// change to either drag the other along.
private final class AuditEffectsSpy: DaemonEnforcementEffects {
    private(set) var callLog: [String] = []

    func persistDeferralStart(_ start: Date?) {
        callLog.append(start == nil ? "persist(nil)" : "persist(date)")
    }

    func cancelPendingShutdown() {
        callLog.append("cancel")
    }

    func issueShutdown() {
        callLog.append("shutdown")
    }

    func clearDeadlineShadow() {
        callLog.append("clearShadow")
    }
}

/// Audit coverage for the privileged daemon's actions.
///
/// These are the highest-consequence records Curfew writes — this process runs
/// as root and can power the machine off — so each one is pinned to the effect
/// it claims to describe. The records are emitted from
/// `DaemonEnforcementRuntime.apply` rather than from the loop or from a
/// decorator on `DaemonEnforcementEffects`, because `apply` is the single
/// point where a decision becomes a machine action: the same `if` that calls
/// the effect writes the line, so the log cannot report a cancellation that
/// never happened, or miss one that did.
struct DaemonAuditWiringTests {
    private let bound = ProtectedWorkPolicy.default.maximumDeferral
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)

    private var window: LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStart,
            scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
            kind: .scheduledTime
        )
    }

    /// A runtime wired to a recording log, plus the spies to assert against.
    private struct Harness {
        var runtime: DaemonEnforcementRuntime
        let writer: RecordingAuditWriter
        let effects: AuditEffectsSpy
    }

    private func makeHarness() -> Harness {
        let writer = RecordingAuditWriter()
        return Harness(
            runtime: DaemonEnforcementRuntime(
                auditLog: AuditLog(stream: .daemon, writer: writer)
            ),
            writer: writer,
            effects: AuditEffectsSpy()
        )
    }

    /// One full tick: decide, then apply. Mirrors `main.swift`, including
    /// feeding `shutdownIssued` back into the next decision.
    @discardableResult
    private func tick(
        _ runtime: inout DaemonEnforcementRuntime,
        effects: AuditEffectsSpy,
        at now: Date,
        heartbeatAge: TimeInterval = 600,
        hasWork: Bool = false,
        breakGlass: Bool = false,
        marker: Date? = nil,
        deadline: LockoutDeadlineRecord? = nil
    ) -> DaemonEnforcementRuntime.LogEvent {
        let outcome = DaemonEnforcementDecision.evaluate(
            DaemonEnforcementDecision.Input(
                now: now,
                deadline: deadline ?? window,
                breakGlassActive: breakGlass,
                heartbeatAge: heartbeatAge,
                heartbeatTimeout: 90,
                hasActiveProtectedWork: hasWork,
                maximumDeferral: bound,
                persistedDeferralStart: marker,
                shutdownAlreadyIssued: runtime.shutdownIssued
            )
        )
        return runtime.apply(outcome, effects: effects, now: now)
    }

    private func detailString(_ record: AuditRecord, _ key: String) -> String? {
        guard case .string(let value)? = record.detail[key] else { return nil }
        return value
    }

    // MARK: - Shutdown

    @Test("Issuing the root shutdown is recorded once")
    func shutdownIssueIsRecorded() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&harness.runtime, effects: effects, at: incident)
        // A second tick must not double-record: the decision suppresses a
        // repeat issue while one is in flight.
        tick(&harness.runtime, effects: effects, at: incident.addingTimeInterval(15))

        #expect(writer.records(ofType: .daemonShutdownIssued).count == 1)
        let record = try #require(writer.first(.daemonShutdownIssued))
        #expect(record.actor.token == "daemon")
        #expect(record.stream == .daemon)
    }

    @Test("Work claimed inside the shutdown's minute records the cancellation and its reason")
    func protectedWorkCancellationIsRecorded() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&harness.runtime, effects: effects, at: incident)
        tick(&harness.runtime, effects: effects, at: incident.addingTimeInterval(15), hasWork: true)

        // The record and the effect are written by the same branch, so one
        // without the other is the failure this test exists to catch.
        #expect(effects.callLog.contains("cancel"))
        let record = try #require(writer.first(.daemonShutdownCancelled))
        #expect(detailString(record, "reason") == "protected_work")
        #expect(record.actor.token == "daemon")
    }

    @Test("A break-glass stand-down records the cancellation as break_glass")
    func breakGlassCancellationIsRecorded() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&harness.runtime, effects: effects, at: incident)
        tick(
            &harness.runtime,
            effects: effects,
            at: incident.addingTimeInterval(15),
            breakGlass: true
        )

        let record = try #require(writer.first(.daemonShutdownCancelled))
        #expect(detailString(record, "reason") == "break_glass")
    }

    @Test("A lockout that ends mid-countdown records the cancellation as lockout_ended")
    func lockoutEndCancellationIsRecorded() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&harness.runtime, effects: effects, at: incident)
        // Deadline gone: the window is over, and powering the Mac off after a
        // legitimate unlock is pure harm.
        tick(
            &harness.runtime,
            effects: effects,
            at: incident.addingTimeInterval(15),
            deadline: LockoutDeadlineRecord(
                lockoutStartedAt: lockoutStart,
                scheduledUnlockAt: incident,
                kind: .scheduledTime
            )
        )

        let record = try #require(writer.first(.daemonShutdownCancelled))
        #expect(detailString(record, "reason") == "lockout_ended")
    }

    @Test("A recovered heartbeat records no cancellation, because none happens")
    func recoveredHeartbeatRecordsNoCancellation() {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&harness.runtime, effects: effects, at: incident)
        // `.wait` deliberately does not cancel — cancelling here would price
        // the bypass at nothing. The log must not claim otherwise.
        tick(
            &harness.runtime,
            effects: effects,
            at: incident.addingTimeInterval(15),
            heartbeatAge: 0
        )

        #expect(effects.callLog.contains("cancel") == false)
        #expect(writer.records(ofType: .daemonShutdownCancelled).isEmpty)
    }

    // MARK: - Stand-down and hold

    @Test("A break-glass stand-down is recorded on the transition, not every tick")
    func standDownIsRecordedOnce() {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        var now = lockoutStart.addingTimeInterval(300)

        for _ in 0 ..< 5 {
            tick(&harness.runtime, effects: effects, at: now, breakGlass: true)
            now = now.addingTimeInterval(15)
        }

        #expect(writer.records(ofType: .daemonStandDown).count == 1)
    }

    @Test("A hold is recorded once per deferral window, not once per tick")
    func holdIsRecordedOncePerWindow() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let start = lockoutStart.addingTimeInterval(300)
        var now = start

        for _ in 0 ..< 6 {
            tick(&harness.runtime, effects: effects, at: now, hasWork: true, marker: start)
            now = now.addingTimeInterval(15)
        }

        #expect(writer.records(ofType: .daemonShutdownHeld).count == 1)
        let record = try #require(writer.first(.daemonShutdownHeld))
        #expect(detailString(record, "until") != nil)
    }

    // MARK: - Deferral window

    @Test("A fresh runtime does not report a deferral window closing that never opened")
    func noSpuriousDeferralCloseOnStart() {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects

        tick(&harness.runtime, effects: effects, at: lockoutStart.addingTimeInterval(300))

        #expect(writer.records(ofType: .daemonDeferralClosed).isEmpty)
        #expect(writer.records(ofType: .daemonDeferralOpened).isEmpty)
    }

    @Test("The bounded deferral window records one open and one close")
    func deferralWindowOpenAndCloseAreRecorded() throws {
        var harness = makeHarness()
        let writer = harness.writer
        let effects = harness.effects
        let start = lockoutStart.addingTimeInterval(300)

        // Work claimed while a shutdown is due: the window opens.
        tick(&harness.runtime, effects: effects, at: start, hasWork: true)
        tick(
            &harness.runtime,
            effects: effects,
            at: start.addingTimeInterval(15),
            hasWork: true,
            marker: start
        )
        // Work finishes: the window closes.
        tick(&harness.runtime, effects: effects, at: start.addingTimeInterval(30), marker: start)

        #expect(writer.records(ofType: .daemonDeferralOpened).count == 1)
        #expect(writer.records(ofType: .daemonDeferralClosed).count == 1)
        let closed = try #require(writer.first(.daemonDeferralClosed))
        #expect(closed.actor.token == "daemon")
    }
}
