@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for the privileged daemon's tick decision.
///
/// The daemon used to be a bare `while true` loop in `main.swift` with no
/// seam to test, and it shipped a bug because of it: the deferral marker was
/// written only on the branch where a shutdown was due, so a heartbeat that
/// recovered left a spent window on disk and the next genuine incident in the
/// same lockout got no grace at all. `recoveryClosesTheWindowWithinOneLockout`
/// is that regression.
struct DaemonEnforcementDecisionTests {
    private let bound = ProtectedWorkPolicy.default.maximumDeferral
    private let timeout: TimeInterval = 90
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)

    private var window: LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStart,
            scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
            kind: .scheduledTime
        )
    }

    /// One tick. `marker` stands in for the root-owned file on disk.
    private func tick(
        at now: Date,
        heartbeatAge: TimeInterval,
        hasWork: Bool = true,
        marker: Date? = nil,
        breakGlass: Bool = false,
        alreadyIssued: Bool = false,
        deadline: LockoutDeadlineRecord? = nil
    ) -> DaemonEnforcementDecision.Outcome {
        DaemonEnforcementDecision.evaluate(
            DaemonEnforcementDecision.Input(
                now: now,
                deadline: deadline ?? window,
                breakGlassActive: breakGlass,
                heartbeatAge: heartbeatAge,
                heartbeatTimeout: timeout,
                hasActiveProtectedWork: hasWork,
                maximumDeferral: bound,
                persistedDeferralStart: marker,
                shutdownAlreadyIssued: alreadyIssued
            )
        )
    }

    // MARK: - The regression

    @Test(
        "A recovered heartbeat closes the window, so a later incident gets its own grace"
    )
    func recoveryClosesTheWindowWithinOneLockout() {
        // The marker survives across ticks exactly as the file does.
        var marker: Date?

        // Episode one: the app drops out — say it crashed and relaunched —
        // while an agent is mid-task. A window opens.
        let firstIncident = lockoutStart.addingTimeInterval(60)
        var outcome = tick(at: firstIncident, heartbeatAge: 120, marker: marker)
        marker = outcome.deferralStartedAt
        #expect(outcome.action == .hold(until: firstIncident.addingTimeInterval(bound)))
        #expect(marker == firstIncident)

        // The app comes back. Nothing is due any more, so the window must
        // close — this is the line that used to be missing.
        let recovered = firstIncident.addingTimeInterval(30)
        outcome = tick(at: recovered, heartbeatAge: 5, marker: marker)
        marker = outcome.deferralStartedAt
        #expect(outcome.action == .wait)
        #expect(marker == nil)

        // Episode two: a separate, genuine incident later than the first
        // window's deadline, agent still working. Before the fix the stale
        // marker made this `.shutDown` on the very first tick.
        let secondIncident = firstIncident.addingTimeInterval(bound + 600)
        outcome = tick(at: secondIncident, heartbeatAge: 120, marker: marker)
        marker = outcome.deferralStartedAt
        #expect(outcome.action == .hold(until: secondIncident.addingTimeInterval(bound)))
        #expect(marker == secondIncident)
    }

    @Test("A marker left over from an earlier lockout is ignored")
    func staleMarkerFromAPreviousWindowIsIgnored() {
        // The daemon can be killed mid-window — `launchctl bootout`, a power
        // cut — leaving the marker behind for the next night.
        let lastNight = lockoutStart.addingTimeInterval(-20 * 60 * 60)
        let incident = lockoutStart.addingTimeInterval(300)

        let outcome = tick(at: incident, heartbeatAge: 120, marker: lastNight)
        #expect(outcome.action == .hold(until: incident.addingTimeInterval(bound)))
        #expect(outcome.deferralStartedAt == incident)
    }

    @Test("A marker dated in the future is ignored rather than extending the hold")
    func futureDatedMarkerIsIgnored() {
        let incident = lockoutStart.addingTimeInterval(300)
        let skewed = incident.addingTimeInterval(3600)

        let outcome = tick(at: incident, heartbeatAge: 120, marker: skewed)
        #expect(outcome.action == .hold(until: incident.addingTimeInterval(bound)))
        #expect(outcome.deferralStartedAt == incident)
    }

    // MARK: - The bound still holds

    @Test("One continuous incident is still bounded")
    func continuousIncidentIsBounded() {
        var marker: Date?
        let incident = lockoutStart.addingTimeInterval(60)

        // Ticking through the window must not extend it.
        for offset in stride(from: 0.0, to: bound, by: 15 * 60) {
            let outcome = tick(
                at: incident.addingTimeInterval(offset),
                heartbeatAge: 120,
                marker: marker
            )
            marker = outcome.deferralStartedAt
            #expect(outcome.action == .hold(until: incident.addingTimeInterval(bound)))
        }

        let outcome = tick(
            at: incident.addingTimeInterval(bound),
            heartbeatAge: 120,
            marker: marker
        )
        #expect(outcome.action == .shutDown)
    }

    @Test("A daemon restart mid-incident resumes the same window")
    func restartResumesTheSameWindow() {
        let incident = lockoutStart.addingTimeInterval(60)
        // Fresh process, marker read off disk, bound already spent.
        let outcome = tick(
            at: incident.addingTimeInterval(bound + 1),
            heartbeatAge: 120,
            marker: incident
        )
        #expect(outcome.action == .shutDown)
    }

    // MARK: - Everything else the tick decides

    @Test("A stale heartbeat with no protected work shuts down immediately")
    func noProtectedWorkShutsDown() {
        let outcome = tick(
            at: lockoutStart.addingTimeInterval(300),
            heartbeatAge: 120,
            hasWork: false
        )
        #expect(outcome.action == .shutDown)
        #expect(outcome.deferralStartedAt == nil)
    }

    @Test("A fresh heartbeat never shuts down, work or no work")
    func freshHeartbeatWaits() {
        for hasWork in [true, false] {
            let outcome = tick(
                at: lockoutStart.addingTimeInterval(300),
                heartbeatAge: 5,
                hasWork: hasWork
            )
            #expect(outcome.action == .wait)
            #expect(outcome.deferralStartedAt == nil)
        }
    }

    @Test("The shutdown is issued once, not on every pass")
    func shutdownIsNotReissued() {
        let outcome = tick(
            at: lockoutStart.addingTimeInterval(300),
            heartbeatAge: 120,
            hasWork: false,
            alreadyIssued: true
        )
        #expect(outcome.action == .wait)
    }

    @Test("Break-glass outranks everything and clears the window")
    func breakGlassStandsDownAndClearsTheMarker() {
        let incident = lockoutStart.addingTimeInterval(300)
        let outcome = tick(
            at: incident,
            heartbeatAge: 120,
            marker: incident.addingTimeInterval(-60),
            breakGlass: true
        )
        #expect(outcome.action == .standDown)
        #expect(outcome.deferralStartedAt == nil)
    }

    @Test("No deadline, or an elapsed one, exits and clears the window")
    func exitPathsClearTheMarker() {
        let noDeadline = DaemonEnforcementDecision.evaluate(
            DaemonEnforcementDecision.Input(now: lockoutStart, deadline: nil)
        )
        #expect(noDeadline.action == .exit)
        #expect(noDeadline.deferralStartedAt == nil)

        let elapsed = tick(
            at: window.scheduledUnlockAt.addingTimeInterval(1),
            heartbeatAge: 120,
            marker: lockoutStart.addingTimeInterval(60)
        )
        #expect(elapsed.action == .exit)
        #expect(elapsed.deferralStartedAt == nil)
    }
}
