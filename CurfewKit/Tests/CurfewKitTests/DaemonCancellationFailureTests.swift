import CurfewKit
import Foundation
import Testing

struct DaemonCancellationFailureTests {
    @Test("Cancellation failures retain pending state and retry before hold, stand-down, or exit")
    func failedCancellationRetries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let actions: [DaemonEnforcementDecision.Action] = [
            .standDown,
            .hold(until: now.addingTimeInterval(300)),
            .exit
        ]
        for action in actions {
            let writer = CancellationAuditWriter()
            var runtime = DaemonEnforcementRuntime(auditLog: AuditLog(
                stream: .daemon,
                writer: writer
            ))
            let effects = FailingCancellationEffects()
            runtime.apply(
                .init(action: .shutDown, deferralStartedAt: nil),
                effects: effects,
                now: now
            )
            runtime.apply(
                .init(
                    action: action,
                    deferralStartedAt: nil,
                    cancelsPendingShutdown: runtime.shutdownIssued
                ),
                effects: effects,
                now: now
            )
            #expect(runtime.shutdownIssued)
            #expect(!runtime.shouldExit)
            #expect(effects.shadowClears == 0)
            #expect(writer.records.filter { $0.event == .daemonShutdownCancelled }.isEmpty)
            let failure = writer.records.first { $0.event == .daemonShutdownFailed }
            #expect(failure?.detail["operation"] == .string("cancel_pending_shutdown"))

            effects.failCancellation = false
            runtime.apply(
                .init(
                    action: action,
                    deferralStartedAt: nil,
                    cancelsPendingShutdown: runtime.shutdownIssued
                ),
                effects: effects,
                now: now.addingTimeInterval(15)
            )
            #expect(effects.cancellations == 2)
            #expect(!runtime.shutdownIssued)
            #expect(writer.records.filter { $0.event == .daemonShutdownCancelled }.count == 1)
            #expect(runtime.shouldExit == (action == .exit))
        }
    }

    @Test("A failed shutdown dispatch remains eligible for the next policy tick")
    func failedDispatchRetries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = CancellationAuditWriter()
        var runtime = DaemonEnforcementRuntime(auditLog: AuditLog(stream: .daemon, writer: writer))
        let effects = FailingCancellationEffects()
        effects.failDispatch = true
        let first = runtime.apply(
            dueShutdown(at: now, alreadyIssued: runtime.shutdownIssued),
            effects: effects,
            now: now
        )
        #expect(first != .issuedShutdown)
        #expect(!runtime.shutdownIssued)
        #expect(writer.records.filter { $0.event == .daemonShutdownIssued }.isEmpty)
        let failure = writer.records.first { $0.event == .daemonShutdownFailed }
        #expect(failure?.detail["operation"] == .string("issue_shutdown"))

        effects.failDispatch = false
        let later = now.addingTimeInterval(15)
        let retry = runtime.apply(
            dueShutdown(at: later, alreadyIssued: runtime.shutdownIssued),
            effects: effects,
            now: later
        )
        #expect(retry == .issuedShutdown)
        #expect(effects.dispatches == 2)
        #expect(runtime.shutdownIssued)
        #expect(writer.records.filter { $0.event == .daemonShutdownIssued }.count == 1)
    }

    @Test(
        "Development disarm never forwards a failed cancellation effect"
    )
    func developmentRemainsDisarmed() {
        let underlying = FailingCancellationEffects()
        let development = DevelopmentDaemonEffects(underlying: underlying)
        development.cancelPendingShutdown()
        #expect(underlying.cancellations == 0)
    }
}

private final class FailingCancellationEffects: DaemonEnforcementEffects {
    var failCancellation = true
    var failDispatch = false
    var dispatches = 0
    var cancellations = 0
    var shadowClears = 0

    func persistDeferralStart(_ start: Date?) {}

    func cancelPendingShutdown() throws {
        cancellations += 1
        if failCancellation {
            throw CocoaError(.executableNotLoadable)
        }
    }

    func issueShutdown() throws {
        dispatches += 1
        if failDispatch {
            throw CocoaError(.executableNotLoadable)
        }
    }

    func clearDeadlineShadow() {
        shadowClears += 1
    }
}

private final class CancellationAuditWriter: AuditLogWriting {
    var records: [AuditRecord] = []

    func append(_ record: AuditRecord) {
        records.append(record)
    }
}

private func dueShutdown(at now: Date, alreadyIssued: Bool) -> DaemonEnforcementDecision.Outcome {
    DaemonEnforcementDecision.evaluate(.init(
        now: now,
        deadline: LockoutDeadlineRecord(
            lockoutStartedAt: now.addingTimeInterval(-300),
            scheduledUnlockAt: now.addingTimeInterval(3600),
            kind: .scheduledTime
        ),
        heartbeatAge: 600,
        shutdownAlreadyIssued: alreadyIssued
    ))
}
