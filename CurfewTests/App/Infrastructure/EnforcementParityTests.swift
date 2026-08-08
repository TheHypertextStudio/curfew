@testable import Curfew
import Foundation
import Testing

/// Cross-checks that the app and the privileged daemon reach the same verdict.
///
/// The carve-out only works if both kill paths agree about when it is safe to
/// destroy the user's background work. They are separate processes on separate
/// triggers at separate privilege levels, so nothing enforces that agreement
/// except `DestructiveActionGate` — and the first cut of this branch drifted
/// anyway, because the app treated a break-glass release as terminal while the
/// daemon re-read it every tick. Revoking re-armed the daemon and left the app
/// stood down for the night.
///
/// These tests run one scenario through both paths and compare, so the next
/// divergence fails here rather than at 22:00 on someone's Mac.
@MainActor
struct EnforcementParityTests {
    private let bound = ProtectedWorkPolicy.default.maximumDeferral
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)

    /// What a path did on one tick, reduced to the only distinction that
    /// matters: did it destroy the user's work, or did it hold off?
    private enum Verdict: Equatable, CustomStringConvertible {
        case heldOff
        case acted

        var description: String {
            self == .acted ? "acted" : "heldOff"
        }
    }

    /// One tick of the app's path.
    private struct AppPath {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true, true, true, true, true])

        /// Arms the workflow so later ticks are past its scheduled delay.
        mutating func arm(at now: Date) {
            step(at: now, breakGlass: false, hasWork: false)
        }

        @discardableResult
        mutating func step(at now: Date, breakGlass: Bool, hasWork: Bool) -> Verdict {
            let before = controller.callLog.count
            workflow.update(
                now: now,
                isLocked: true,
                isEnabled: true,
                delayMinutes: 10,
                controller: controller,
                isActiveDevice: true,
                context: ProtectedWorkContext(
                    policy: .default,
                    hasActiveWork: hasWork,
                    isBreakGlassActive: breakGlass
                )
            )
            return controller.callLog.count > before ? .acted : .heldOff
        }
    }

    /// One tick of the daemon's path, carrying the marker between ticks the
    /// way the root-owned file does.
    private struct DaemonPath {
        let lockoutStart: Date
        var marker: Date?
        var shutdownIssued = false

        mutating func step(at now: Date, breakGlass: Bool, hasWork: Bool) -> Verdict {
            let outcome = DaemonEnforcementDecision.evaluate(
                DaemonEnforcementDecision.Input(
                    now: now,
                    deadline: LockoutDeadlineRecord(
                        lockoutStartedAt: lockoutStart,
                        scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
                        kind: .scheduledTime
                    ),
                    breakGlassActive: breakGlass,
                    // Always stale: the daemon's trigger is a missing app, and
                    // this suite is about what happens once it has fired.
                    heartbeatAge: 600,
                    heartbeatTimeout: 90,
                    hasActiveProtectedWork: hasWork,
                    maximumDeferral: ProtectedWorkPolicy.default.maximumDeferral,
                    persistedDeferralStart: marker,
                    shutdownAlreadyIssued: shutdownIssued
                )
            )
            marker = outcome.deferralStartedAt
            if outcome.action == .standDown {
                // The daemon cancels a pending shutdown and re-arms, which is
                // what makes a revoke meaningful on its side.
                shutdownIssued = false
            }
            if outcome.action == .shutDown {
                shutdownIssued = true
                return .acted
            }
            return .heldOff
        }
    }

    /// One moment in a scenario: when it happens and what the world looks like.
    private struct Tick {
        let offset: TimeInterval
        let breakGlass: Bool
        let hasWork: Bool
    }

    /// Runs `script` through both paths and returns their per-tick verdicts.
    private func run(_ script: [Tick]) -> (app: [Verdict], daemon: [Verdict]) {
        var app = AppPath()
        var daemon = DaemonPath(lockoutStart: lockoutStart)
        app.arm(at: lockoutStart)

        var appVerdicts: [Verdict] = []
        var daemonVerdicts: [Verdict] = []
        for tick in script {
            let now = lockoutStart.addingTimeInterval(tick.offset)
            appVerdicts.append(
                app.step(at: now, breakGlass: tick.breakGlass, hasWork: tick.hasWork)
            )
            daemonVerdicts.append(
                daemon.step(at: now, breakGlass: tick.breakGlass, hasWork: tick.hasWork)
            )
        }
        return (appVerdicts, daemonVerdicts)
    }

    @Test("Issuing then revoking break-glass moves both paths identically")
    func revokeParity() {
        // Armed → released → released → revoked.
        let verdicts = run([
            Tick(offset: 700, breakGlass: true, hasWork: false),
            Tick(offset: 800, breakGlass: true, hasWork: false),
            Tick(offset: 900, breakGlass: false, hasWork: false)
        ])

        #expect(verdicts.app == verdicts.daemon)
        #expect(verdicts.app == [.heldOff, .heldOff, .acted])
    }

    @Test("Revoking while protected work is live holds both paths, not just one")
    func revokeWithLiveWorkParity() {
        let verdicts = run([
            Tick(offset: 700, breakGlass: true, hasWork: true),
            // Revoked long after the deferral bound would have elapsed had a
            // window been open underneath the release. Neither path may treat
            // that as a spent budget.
            Tick(offset: 700 + bound + 600, breakGlass: false, hasWork: true)
        ])

        #expect(verdicts.app == verdicts.daemon)
        #expect(verdicts.app == [.heldOff, .heldOff])
    }

    @Test("A release arriving after a deferral has begun stands both paths down")
    func releaseAfterDeferralParity() {
        let verdicts = run([
            Tick(offset: 700, breakGlass: false, hasWork: true),
            Tick(offset: 800, breakGlass: true, hasWork: true),
            Tick(offset: 900, breakGlass: true, hasWork: false)
        ])

        #expect(verdicts.app == verdicts.daemon)
        #expect(verdicts.app == [.heldOff, .heldOff, .heldOff])
    }

    @Test("The deferral bound expires at the same tick on both paths")
    func boundedDeferralParity() {
        let verdicts = run([
            Tick(offset: 700, breakGlass: false, hasWork: true),
            Tick(offset: 700 + bound - 60, breakGlass: false, hasWork: true),
            Tick(offset: 700 + bound, breakGlass: false, hasWork: true)
        ])

        #expect(verdicts.app == verdicts.daemon)
        #expect(verdicts.app == [.heldOff, .heldOff, .acted])
    }

    @Test("With nothing holding them back both paths act on the same tick")
    func unblockedParity() {
        let verdicts = run([
            Tick(offset: 700, breakGlass: false, hasWork: false)
        ])

        #expect(verdicts.app == verdicts.daemon)
        #expect(verdicts.app == [.acted])
    }
}
