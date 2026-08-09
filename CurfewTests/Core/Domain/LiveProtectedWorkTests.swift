@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``LiveProtectedWorkMonitor`` — the piece that turns the
/// allowlist from a list of names into an observation of the running machine.
///
/// Declared claims already covered agents that cooperate. These cover the ones
/// that do not: a `claude` run started from a shell, and an engineer working
/// over SSH. Neither files anything, so before this type both destructive
/// paths read "no protected work" and powered the Mac off underneath them.
struct LiveProtectedWorkTests {
    // MARK: - The matching rule

    @Test("A live agent process counts as protected work")
    func liveAgentProcessCounts() {
        let observation = LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: [RunningProcess(processIdentifier: 4242, executableName: "claude")],
            sessions: []
        )

        #expect(observation.isActive)
        #expect(observation.agentProcesses.map(\.processIdentifier) == [4242])
    }

    @Test("An unlisted process holds nothing back")
    func unlistedProcessIsNotProtected() {
        let observation = LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: [
                RunningProcess(processIdentifier: 1, executableName: "Safari"),
                RunningProcess(processIdentifier: 2, executableName: "Music")
            ],
            sessions: []
        )

        #expect(!observation.isActive)
        #expect(observation.agentProcesses.isEmpty)
    }

    @Test("Matching is case-insensitive but exact — no prefixes")
    func matchingIsExactAndCaseInsensitive() {
        let policy = ProtectedWorkPolicy.default

        #expect(policy.defersForProcess(named: "CLAUDE"))
        #expect(policy.defersForProcess(named: "Claude"))
        // A prefix rule here would be an off switch, not a carve-out.
        #expect(!policy.defersForProcess(named: "claudette"))
        #expect(!policy.defersForProcess(named: "cla"))
    }

    /// The reason ``ProtectedWorkPolicy/deferringProcessNames`` exists as a
    /// separate, narrower list. `tmux` is spared from `terminate()` because
    /// killing it would take the work with it — but it is alive on a working
    /// machine essentially always, so letting it open a deferral window would
    /// spend the full hold every night for anyone who uses one.
    @Test("A multiplexer is spared from termination but does not defer shutdown")
    func sparedProcessesDoNotAutomaticallyDefer() {
        let policy = ProtectedWorkPolicy.default

        #expect(policy.protectsApplication(bundleIdentifier: nil, executableName: "tmux"))
        #expect(!policy.defersForProcess(named: "tmux"))

        #expect(policy.protectsApplication(bundleIdentifier: nil, executableName: "screen"))
        #expect(!policy.defersForProcess(named: "screen"))
    }

    @Test("Emptying the deferring list turns liveness-based holds off entirely")
    func emptyListDisablesLivenessDeferral() {
        var policy = ProtectedWorkPolicy.default
        policy.deferringProcessNames = []

        let observation = LiveProtectedWorkMonitor.observe(
            policy: policy,
            processes: [RunningProcess(processIdentifier: 9, executableName: "claude")],
            sessions: []
        )

        #expect(!observation.isActive)
    }

    // MARK: - Remote sessions

    @Test("A session arriving from another host counts as protected work")
    func remoteSessionCounts() {
        let observation = LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: [],
            sessions: [.ssh(from: "studio.local")]
        )

        #expect(observation.isActive)
        #expect(observation.remoteSessions.map(\.remoteHost) == ["studio.local"])
    }

    @Test("A local console session does not")
    func consoleSessionDoesNotCount() {
        let observation = LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: [],
            sessions: [.console()]
        )

        #expect(!observation.isActive)
    }

    @Test("Turning remote sessions off ignores them")
    func remoteSessionsCanBeDisabled() {
        var policy = ProtectedWorkPolicy.default
        policy.defersForRemoteSessions = false

        let observation = LiveProtectedWorkMonitor.observe(
            policy: policy,
            processes: [],
            sessions: [.ssh()]
        )

        #expect(!observation.isActive)
    }

    @Test("The summary names what is holding")
    func summaryNamesTheHolder() {
        let observation = LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: [RunningProcess(processIdentifier: 1, executableName: "claude")],
            sessions: [.ssh(from: "studio.local")]
        )

        #expect(observation.summary == "agents: claude; remote sessions: studio.local")
    }

    // MARK: - The monitor as wired

    @Test("The disabled monitor observes nothing, whatever the machine is doing")
    func disabledMonitorObservesNothing() {
        #expect(!LiveProtectedWorkMonitor.disabled.observe(policy: .default).isActive)
    }

    @Test("The monitor reads both sources through its enumerators")
    func monitorReadsBothSources() {
        let monitor = LiveProtectedWorkMonitor(
            processSource: StubProcessEnumerator(
                processes: [RunningProcess(processIdentifier: 7, executableName: "codex")]
            ),
            sessionSource: StubLoginSessionEnumerator(sessions: [.console()])
        )

        let observation = monitor.observe(policy: .default)
        #expect(observation.isActive)
        #expect(observation.agentProcesses.count == 1)
        #expect(observation.remoteSessions.isEmpty)
    }

    // MARK: - The real readers, against the real machine

    /// The pure rule above is worth nothing if the reader underneath it cannot
    /// actually see a process, so this one spawns a genuine `claude` and reads
    /// it back out of `sysctl`.
    @Test("The real sysctl reader sees a real process under its real name")
    func sysctlReaderSeesASpawnedProcess() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude")
        defer { probe.terminateAndWait() }

        let processes = SysctlProcessEnumerator().runningProcesses()
        let match = processes.first { $0.processIdentifier == probe.processIdentifier }

        #expect(match?.executableName == "claude")
        #expect(LiveProtectedWorkMonitor.observe(
            policy: .default,
            processes: processes,
            sessions: []
        ).isActive)
    }

    @Test("A dead process stops protecting anything")
    func terminatedProcessStopsCounting() throws {
        let probe = try SpawnedProcessProbe(executableName: "claude")
        let pid = probe.processIdentifier
        probe.terminateAndWait()

        // The kernel may not have reaped it the instant `waitUntilExit`
        // returns, so give the table a moment to settle rather than asserting
        // on a race.
        let deadline = Date().addingTimeInterval(5)
        var stillListed = true
        while Date() < deadline, stillListed {
            stillListed = SysctlProcessEnumerator().runningProcesses()
                .contains { $0.processIdentifier == pid }
            if stillListed {
                usleep(20000)
            }
        }

        #expect(!stillListed)
    }

    /// `utmpx` is what `who` reads, and the test host has no way to guarantee a
    /// remote login exists. What can be pinned is that the reader runs against
    /// the real database and returns well-formed records rather than garbage
    /// from a mis-rebound C array — the failure mode that would otherwise show
    /// up only on a machine someone was actually SSHed into.
    @Test("The real utmpx reader returns well-formed sessions")
    func utmpxReaderReturnsWellFormedSessions() {
        let sessions = UtmpxLoginSessionEnumerator().loginSessions()

        for session in sessions {
            #expect(!session.user.isEmpty)
            #expect(!session.user.contains("\0"))
            #expect(!session.remoteHost.contains("\0"))
            #expect(session.isRemote == !session.remoteHost.isEmpty)
        }
    }
}
