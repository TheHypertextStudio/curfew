@testable import Curfew
import Foundation
import Testing

/// Recording stand-in for the machine, so the daemon's side effects can be
/// asserted without a Mac that actually powers off.
private final class DaemonEffectsSpy: DaemonEnforcementEffects {
    /// Ordered log of effects, e.g. `["persist(nil)", "cancel", "shutdown"]`.
    private(set) var callLog: [String] = []
    /// Every value handed to `persistDeferralStart`, in order.
    private(set) var persisted: [Date?] = []

    var cancelCount: Int {
        callLog.count(where: { $0 == "cancel" })
    }

    var shutdownCount: Int {
        callLog.count(where: { $0 == "shutdown" })
    }

    func persistDeferralStart(_ start: Date?) {
        persisted.append(start)
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

/// Behaviour tests for the imperative half of the daemon.
///
/// The pure decision was already well covered; the code that *carried out* the
/// decision was a top-level `while` loop no test could reach, and that is
/// where this branch's bugs kept turning up. `holdCancelsAShutdownAlreadyInFlight`
/// is the one that matters most: `/sbin/shutdown -h +1` executes about a minute
/// after it is issued, so a claim arriving on a tick inside that minute has to
/// call the countdown off, not merely be noted in the log.
struct DaemonEnforcementRuntimeTests {
    private let bound = ProtectedWorkPolicy.default.maximumDeferral
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)

    private var window: LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStart,
            scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
            kind: .scheduledTime
        )
    }

    /// One full tick: decide, then apply. Mirrors `main.swift`, including
    /// feeding `shutdownIssued` back into the next decision.
    @discardableResult
    private func tick(
        _ runtime: inout DaemonEnforcementRuntime,
        effects: DaemonEffectsSpy,
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
        return runtime.apply(outcome, effects: effects)
    }

    // MARK: - The regression

    @Test("Work claimed inside the shutdown's one-minute delay cancels it")
    func holdCancelsAShutdownAlreadyInFlight() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        // Heartbeat stale, nothing protected: the daemon fires.
        #expect(tick(&runtime, effects: effects, at: incident) == .issuedShutdown)
        #expect(runtime.shutdownIssued)
        #expect(effects.shutdownCount == 1)

        // Fifteen seconds later, still inside `/sbin/shutdown -h +1`'s minute,
        // an agent files a claim. Deciding to hold is not enough — the
        // countdown is already running and will take the machine down with the
        // work unless something kills it.
        let claimArrived = incident.addingTimeInterval(15)
        let event = tick(&runtime, effects: effects, at: claimArrived, hasWork: true)

        #expect(event == .holding(until: claimArrived.addingTimeInterval(bound)))
        #expect(effects.cancelCount == 1)
        #expect(!runtime.shutdownIssued)
    }

    @Test("Cancelling re-arms, so the bound still ends the reprieve")
    func cancellationDoesNotDisarmEnforcement() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&runtime, effects: effects, at: incident)
        let claimArrived = incident.addingTimeInterval(15)
        tick(&runtime, effects: effects, at: claimArrived, hasWork: true)
        // The window the daemon just wrote to its marker file.
        let marker = effects.persisted.last.flatMap(\.self)

        // Work never finishes. Once the bound is spent the daemon fires again.
        let event = tick(
            &runtime,
            effects: effects,
            at: claimArrived.addingTimeInterval(bound),
            hasWork: true,
            marker: marker
        )
        #expect(event == .issuedShutdown)
        #expect(effects.shutdownCount == 2)
        #expect(runtime.shutdownIssued)
    }

    @Test("Break-glass cancels a shutdown already in flight")
    func standDownCancels() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&runtime, effects: effects, at: incident)
        let event = tick(
            &runtime,
            effects: effects,
            at: incident.addingTimeInterval(15),
            breakGlass: true
        )

        #expect(event == .standingDown)
        #expect(effects.cancelCount == 1)
        #expect(!runtime.shutdownIssued)
    }

    @Test("A window that ends mid-countdown cancels rather than powering off after unlock")
    func exitCancels() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = window.scheduledUnlockAt.addingTimeInterval(-30)

        tick(&runtime, effects: effects, at: incident)
        #expect(effects.shutdownCount == 1)

        let event = tick(
            &runtime,
            effects: effects,
            at: window.scheduledUnlockAt.addingTimeInterval(1)
        )
        #expect(event == .exiting)
        #expect(effects.cancelCount == 1)
        #expect(runtime.shouldExit)
    }

    @Test("A recovered heartbeat does not cancel, so going missing still costs the machine")
    func recoveryDoesNotCancel() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&runtime, effects: effects, at: incident)
        // Relaunching Curfew inside the minute must not buy a free pass, or
        // the daemon's deterrent is worth nothing.
        let event = tick(
            &runtime,
            effects: effects,
            at: incident.addingTimeInterval(15),
            heartbeatAge: 2
        )
        #expect(event == .idle)
        #expect(effects.cancelCount == 0)
        #expect(runtime.shutdownIssued)
    }

    // MARK: - Bookkeeping

    @Test("The marker is written on every tick, nil included")
    func markerIsAlwaysWritten() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&runtime, effects: effects, at: incident, hasWork: true)
        tick(&runtime, effects: effects, at: incident.addingTimeInterval(15), heartbeatAge: 2)
        tick(&runtime, effects: effects, at: incident.addingTimeInterval(30), breakGlass: true)

        #expect(effects.persisted.count == 3)
        #expect(effects.persisted[0] == incident)
        #expect(effects.persisted[1] == nil)
        #expect(effects.persisted[2] == nil)
    }

    @Test("Stand-down is logged once, not on every pass")
    func standDownLogsOnTheTransition() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        #expect(
            tick(&runtime, effects: effects, at: incident, breakGlass: true) == .standingDown
        )
        #expect(
            tick(
                &runtime,
                effects: effects,
                at: incident.addingTimeInterval(15),
                breakGlass: true
            ) == .idle
        )
        // Revoked, then released again: the second release logs afresh.
        tick(&runtime, effects: effects, at: incident.addingTimeInterval(30))
        #expect(
            tick(
                &runtime,
                effects: effects,
                at: incident.addingTimeInterval(45),
                breakGlass: true
            ) == .standingDown
        )
    }

    @Test("Exit clears the deadline shadow and stops the loop")
    func exitClearsTheShadow() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()

        let outcome = DaemonEnforcementDecision.evaluate(
            DaemonEnforcementDecision.Input(now: lockoutStart, deadline: nil)
        )
        #expect(runtime.apply(outcome, effects: effects) == .exiting)
        #expect(effects.callLog.contains("clearShadow"))
        #expect(runtime.shouldExit)
    }

    @Test("The shutdown is issued once while it is pending")
    func shutdownIsNotReissued() {
        var runtime = DaemonEnforcementRuntime()
        let effects = DaemonEffectsSpy()
        let incident = lockoutStart.addingTimeInterval(300)

        tick(&runtime, effects: effects, at: incident)
        tick(&runtime, effects: effects, at: incident.addingTimeInterval(15))
        tick(&runtime, effects: effects, at: incident.addingTimeInterval(30))
        #expect(effects.shutdownCount == 1)
    }
}
