@testable import Curfew
import Foundation
import Testing

/// The two scenarios the carve-out actually promises, driven end to end
/// through both kill paths.
///
/// `ProtectedWorkShutdownTests` proves the machinery works once something has
/// set `hasActiveWork`. These prove the thing that sets it: an agent that never
/// files a claim, and a person logged in over the network, both of which were
/// invisible to enforcement before ``LiveProtectedWorkMonitor``.
///
/// The agent scenarios spawn a real process and read it back out of the
/// kernel. A fixture would have passed just as happily against a reader that
/// never worked.
@MainActor
struct ProtectedWorkLivenessTests {
    private let lockoutStart = Date(timeIntervalSince1970: 1_800_000_000)
    private let heartbeatTimeout: TimeInterval = 90

    private var window: LockoutDeadlineRecord {
        LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStart,
            scheduledUnlockAt: lockoutStart.addingTimeInterval(10 * 60 * 60),
            kind: .scheduledTime
        )
    }

    /// Drives the app's auto-shutdown workflow one tick, reading protected
    /// work from `stores` exactly as `CurfewAppModel.protectedWorkContext()`
    /// does.
    private func tickApp(
        _ workflow: inout ShutdownWorkflow,
        at now: Date,
        controller: ShutdownControllerSpy,
        stores: ProtectedWorkStores,
        policy: ProtectedWorkPolicy = .default
    ) {
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: controller,
            isActiveDevice: true,
            context: ProtectedWorkContext(
                policy: policy,
                hasActiveWork: stores.hasProtectedWork(now: now, policy: policy),
                isBreakGlassActive: false
            )
        )
    }

    /// One privileged-daemon tick with the heartbeat long gone — the state in
    /// which the daemon roots the Mac off.
    private func tickDaemon(
        at now: Date,
        stores: ProtectedWorkStores,
        policy: ProtectedWorkPolicy = .default
    ) -> DaemonEnforcementDecision.Outcome {
        DaemonEnforcementDecision.evaluate(
            DaemonEnforcementDecision.Input(
                now: now,
                deadline: window,
                breakGlassActive: false,
                heartbeatAge: heartbeatTimeout + 60,
                heartbeatTimeout: heartbeatTimeout,
                hasActiveProtectedWork: stores.hasProtectedWork(now: now, policy: policy),
                maximumDeferral: policy.maximumDeferral
            )
        )
    }

    /// Stores with no claims file and a monitor pointed at whatever is given.
    private func stores(
        processes: RunningProcessEnumerating,
        sessions: LoginSessionEnumerating = StubLoginSessionEnumerator(sessions: [])
    ) -> ProtectedWorkStores {
        ProtectedWorkStores(
            claims: ProtectedWorkStore(
                recordURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("curfew-no-claims-\(UUID().uuidString).json")
            ),
            live: LiveProtectedWorkMonitor(
                processSource: processes,
                sessionSource: sessions
            )
        )
    }

    // MARK: - Acceptance: a real agent job survives

    @Test("A real running agent job defers auto-shutdown without filing a claim")
    func realAgentProcessDefersAutoShutdown() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude")
        defer { probe.terminateAndWait() }

        // The real reader against the real process table, narrowed to the pid
        // this test spawned so the verdict is about that process and not about
        // whatever else the machine happens to be running.
        let stores = stores(
            processes: ScopedProcessEnumerator(pids: [probe.processIdentifier])
        )
        #expect(stores.hasProtectedWork(now: lockoutStart, policy: .default))

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])

        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(
            &workflow,
            at: lockoutStart.addingTimeInterval(600),
            controller: controller,
            stores: stores
        )

        guard case .deferred = workflow.phase else {
            Issue.record("expected the shutdown to be held, got \(workflow.phase)")
            return
        }
        // Nothing was terminated and the Mac was never told to power off.
        #expect(controller.callLog.isEmpty)
    }

    @Test("A real running agent job defers the privileged daemon's shutdown too")
    func realAgentProcessDefersDaemonShutdown() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude")
        defer { probe.terminateAndWait() }

        let outcome = tickDaemon(
            at: lockoutStart.addingTimeInterval(300),
            stores: stores(
                processes: ScopedProcessEnumerator(pids: [probe.processIdentifier])
            )
        )

        guard case .hold = outcome.action else {
            Issue.record("expected the daemon to hold, got \(outcome.action)")
            return
        }
        #expect(outcome.deferralStartedAt != nil)
    }

    /// The whole promise in one sequence: with auto-shutdown enabled *and* the
    /// daemon's heartbeat window blown, a live agent holds both paths — and
    /// once it exits, both fire.
    @Test("Both kill paths hold for a live agent and resume once it exits")
    func bothPathsHoldThenResume() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude")
        let stores = stores(
            processes: ScopedProcessEnumerator(pids: [probe.processIdentifier])
        )
        let due = lockoutStart.addingTimeInterval(600)

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(&workflow, at: due, controller: controller, stores: stores)

        guard case .deferred = workflow.phase else {
            Issue.record("expected a hold while the agent runs, got \(workflow.phase)")
            return
        }
        guard case .hold = tickDaemon(at: due, stores: stores).action else {
            Issue.record("expected the daemon to hold while the agent runs")
            return
        }

        // The job finishes. Nothing has to notice or clean up — the process is
        // simply gone from the table on the next read.
        probe.terminateAndWait()
        try waitUntilGone(probe.processIdentifier)

        tickApp(&workflow, at: due.addingTimeInterval(60), controller: controller, stores: stores)
        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])

        let resumed = tickDaemon(at: due.addingTimeInterval(60), stores: stores)
        #expect(resumed.action == .shutDown)
    }

    // MARK: - Acceptance: an SSH session survives

    /// A real inbound SSH session cannot be created from a unit test — it
    /// needs Remote Login enabled on the host and credentials to log in with,
    /// neither of which a test may go and switch on. What is real here is the
    /// record shape: ``LoginSession/ssh(user:line:from:)`` is the `utmpx`
    /// entry macOS writes for a network login, and
    /// ``UtmpxLoginSessionEnumerator`` is verified against the live database
    /// in `LiveProtectedWorkTests`.
    @Test("An SSH session defers auto-shutdown")
    func sshSessionDefersAutoShutdown() {
        let stores = stores(
            processes: StubProcessEnumerator(processes: []),
            sessions: StubLoginSessionEnumerator(sessions: [.console(), .ssh(from: "studio.local")])
        )

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(
            &workflow,
            at: lockoutStart.addingTimeInterval(600),
            controller: controller,
            stores: stores
        )

        guard case .deferred = workflow.phase else {
            Issue.record("expected the shutdown to be held, got \(workflow.phase)")
            return
        }
        #expect(controller.callLog.isEmpty)
    }

    @Test("An SSH session defers the privileged daemon's shutdown")
    func sshSessionDefersDaemonShutdown() {
        let outcome = tickDaemon(
            at: lockoutStart.addingTimeInterval(300),
            stores: stores(
                processes: StubProcessEnumerator(processes: []),
                sessions: StubLoginSessionEnumerator(sessions: [.ssh(from: "studio.local")])
            )
        )

        guard case .hold = outcome.action else {
            Issue.record("expected the daemon to hold for the SSH session, got \(outcome.action)")
            return
        }
    }

    @Test("A console-only login does not defer either path")
    func consoleSessionDefersNothing() {
        let stores = stores(
            processes: StubProcessEnumerator(processes: []),
            sessions: StubLoginSessionEnumerator(sessions: [.console()])
        )

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(
            &workflow,
            at: lockoutStart.addingTimeInterval(600),
            controller: controller,
            stores: stores
        )

        #expect(workflow.phase == .completed)
        #expect(tickDaemon(at: lockoutStart.addingTimeInterval(300), stores: stores).action
            == .shutDown)
    }

    // MARK: - Acceptance: nothing else gets a reprieve

    /// The carve-out must not become a general escape hatch. A real process
    /// that is not on the list is treated exactly as it was before this
    /// existed: both paths proceed, and the terminate sweep is still handed
    /// the allowlist to filter on.
    @Test("A real non-allowlisted process is still terminated exactly as before")
    func nonAllowlistedProcessIsStillTerminated() throws {
        let probe = try SpawnedProcessProbe(executableName: "curfew-noise")
        defer { probe.terminateAndWait() }

        let stores = stores(
            processes: ScopedProcessEnumerator(pids: [probe.processIdentifier])
        )
        // It is running, and it is visible to the reader — it simply is not on
        // the list, so it buys nothing.
        #expect(probe.isVisibleToEnumerator(SysctlProcessEnumerator()))
        #expect(!stores.hasProtectedWork(now: lockoutStart, policy: .default))

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(
            &workflow,
            at: lockoutStart.addingTimeInterval(600),
            controller: controller,
            stores: stores
        )

        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])
        #expect(controller.lastSparedPolicy == .default)

        let outcome = tickDaemon(at: lockoutStart.addingTimeInterval(300), stores: stores)
        #expect(outcome.action == .shutDown)
    }

    /// Liveness widens what counts as protected work, so it must not widen how
    /// long the hold lasts. The bound is still measured from the moment the
    /// action came due, and still expires with the agent still running.
    @Test("A liveness hold is bounded exactly like a declared one")
    func livenessHoldIsBounded() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude", lifetimeSeconds: 300)
        defer { probe.terminateAndWait() }

        let stores = stores(
            processes: ScopedProcessEnumerator(pids: [probe.processIdentifier])
        )
        let due = lockoutStart.addingTimeInterval(600)
        let bound = ProtectedWorkPolicy.default.maximumDeferral

        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        tickApp(&workflow, at: lockoutStart, controller: controller, stores: stores)
        tickApp(&workflow, at: due, controller: controller, stores: stores)
        // The clock moves past the bound; the agent is still very much alive.
        tickApp(
            &workflow,
            at: due.addingTimeInterval(bound + 1),
            controller: controller,
            stores: stores
        )

        #expect(stores.hasProtectedWork(now: due, policy: .default))
        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])
    }

    // MARK: - Helpers

    private func waitUntilGone(_ pid: Int32) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let listed = SysctlProcessEnumerator().runningProcesses()
                .contains { $0.processIdentifier == pid }
            if !listed {
                return
            }
            usleep(20000)
        }
        Issue.record("pid \(pid) never left the process table")
    }
}
