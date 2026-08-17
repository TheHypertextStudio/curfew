import Darwin
import Foundation

/// Turns the protected-work allowlist into an *observation of the running
/// machine*, so background agents survive lockout by contract rather than by
/// remembering to announce themselves.
///
/// ``ProtectedWorkStore`` already answers "did anything *declare* work?" — a
/// lease filed by `curfew-ctl work claim` or the `curfew_declare_work` MCP
/// tool. That covers cooperating callers and nothing else. A `claude -p` run
/// started from a shell, or an engineer working over SSH, files no claim, so
/// before this type both destructive paths saw "no protected work" and
/// happily powered the Mac off underneath them.
///
/// The allowlist itself was equally inert for those cases:
/// ``ProtectedWorkPolicy/protectedProcessNames`` is consumed only by
/// `SystemShutdownController.requestGracefulTermination`, which filters
/// `NSWorkspace.runningApplications` — a list of LaunchServices applications
/// that a bare CLI process is never in. Sparing an app Curfew was never going
/// to `terminate()` anyway is not a carve-out.
///
/// So this type reads the process table and the login database directly, and
/// feeds the answer into the same `hasActiveProtectedWork` input the app and
/// the daemon already share through ``DestructiveActionGate``. One signal,
/// both paths, same verdict.
public struct LiveProtectedWorkMonitor {
    /// What the machine looks like right now, as far as the carve-out cares.
    public struct Observation: Equatable, Sendable {
        /// Live processes whose executable name is in
        /// ``ProtectedWorkPolicy/deferringProcessNames``.
        public var agentProcesses: [RunningProcess]

        /// Live login sessions arriving from another host, when
        /// ``ProtectedWorkPolicy/defersForRemoteSessions`` is on.
        public var remoteSessions: [LoginSession]

        public init(agentProcesses: [RunningProcess] = [], remoteSessions: [LoginSession] = []) {
            self.agentProcesses = agentProcesses
            self.remoteSessions = remoteSessions
        }

        /// Whether anything observed here should hold a destructive action off.
        public var isActive: Bool {
            !agentProcesses.isEmpty || !remoteSessions.isEmpty
        }

        /// One line naming what is holding, for the audit stream and the
        /// daemon's log. Empty when nothing is.
        public var summary: String {
            var parts: [String] = []
            if !agentProcesses.isEmpty {
                let names = Set(agentProcesses.map(\.executableName)).sorted()
                parts.append("agents: \(names.joined(separator: ", "))")
            }
            if !remoteSessions.isEmpty {
                let hosts = Set(remoteSessions.map(\.remoteHost)).sorted()
                parts.append("remote sessions: \(hosts.joined(separator: ", "))")
            }
            return parts.joined(separator: "; ")
        }
    }

    private let processSource: RunningProcessEnumerating
    private let sessionSource: LoginSessionEnumerating

    public init(
        processSource: RunningProcessEnumerating,
        sessionSource: LoginSessionEnumerating
    ) {
        self.processSource = processSource
        self.sessionSource = sessionSource
    }

    /// Reads the real process table and the real login database.
    public static let system = LiveProtectedWorkMonitor(
        processSource: SysctlProcessEnumerator(),
        sessionSource: UtmpxLoginSessionEnumerator()
    )

    /// Observes nothing. The default everywhere, so a test host — or any
    /// caller that has not deliberately opted in — cannot have its verdict
    /// changed by whatever happens to be running on the machine.
    public static let disabled = LiveProtectedWorkMonitor(
        processSource: EmptyProcessEnumerator(),
        sessionSource: EmptyLoginSessionEnumerator()
    )

    /// Samples the machine and matches it against `policy`.
    public func observe(policy: ProtectedWorkPolicy) -> Observation {
        Self.observe(
            policy: policy,
            processes: processSource.runningProcesses(),
            sessions: sessionSource.loginSessions()
        )
    }

    /// The matching rule, as a pure function over a sampled machine.
    ///
    /// Matching is exact and case-insensitive, deliberately mirroring
    /// ``ProtectedWorkPolicy/protectsApplication(bundleIdentifier:executableName:)``.
    /// A prefix or substring rule would be far too easy to turn into a
    /// blanket hold — `"c"` matching every `claude`, `code`, and `cron` on the
    /// box is not a carve-out, it is an off switch.
    public static func observe(
        policy: ProtectedWorkPolicy,
        processes: [RunningProcess],
        sessions: [LoginSession]
    ) -> Observation {
        let agents = processes.filter { process in
            policy.defersForProcess(named: process.executableName)
        }
        let remote = policy.defersForRemoteSessions
            ? sessions.filter(\.isRemote)
            : []
        return Observation(agentProcesses: agents, remoteSessions: remote)
    }
}

// MARK: - What a sample looks like

/// One process observed alive.
public struct RunningProcess: Equatable, Sendable {
    /// The kernel's pid.
    public let processIdentifier: Int32

    /// The executable's short name — `p_comm`, which the kernel truncates to
    /// `MAXCOMLEN` (16) characters. Every agent CLI worth naming fits; a
    /// longer name must be listed by its truncated form, which is why the
    /// enumerator does not pretend to offer a full path.
    public let executableName: String

    public init(processIdentifier: Int32, executableName: String) {
        self.processIdentifier = processIdentifier
        self.executableName = executableName
    }
}

/// One login session observed in the `utmpx` database — the same source `who`
/// reads.
public struct LoginSession: Equatable, Sendable {
    /// Who is logged in.
    public let user: String

    /// The tty, e.g. `ttys004`.
    public let line: String

    /// Where the login came from. Empty for a local console or window-server
    /// session; a hostname or address for one that arrived over the network.
    public let remoteHost: String

    public init(user: String, line: String, remoteHost: String) {
        self.user = user
        self.line = line
        self.remoteHost = remoteHost
    }

    /// Whether this session came from another machine. This — not the
    /// presence of an `sshd` process — is the honest test: the `sshd`
    /// listener runs whenever Remote Login is enabled, so matching on it
    /// would hold enforcement off every night on any Mac that accepts SSH at
    /// all, session or no session.
    public var isRemote: Bool {
        !remoteHost.isEmpty
    }
}

// MARK: - Sampling the machine

/// Supplies the live process table. Abstracted so the matching rule can be
/// driven from a fixture and the real reader can be tested on its own.
public protocol RunningProcessEnumerating {
    func runningProcesses() -> [RunningProcess]
}

/// Supplies the live login sessions.
public protocol LoginSessionEnumerating {
    func loginSessions() -> [LoginSession]
}

/// Reads every process on the machine via `sysctl(KERN_PROC_ALL)`.
///
/// `p_comm` is used rather than `KERN_PROCARGS2` because the latter refuses to
/// hand a non-root caller another user's argv. The app runs as the user and
/// the daemon runs as root, and the carve-out is worthless if the two of them
/// see different machines.
public struct SysctlProcessEnumerator: RunningProcessEnumerating {
    public init() {}

    public func runningProcesses() -> [RunningProcess] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&name, 4, nil, &length, nil, 0) == 0, length > 0 else {
            return []
        }

        // The table can grow between sizing and reading, so ask for a little
        // slack and trust the byte count `sysctl` reports back rather than
        // the one it gave us first.
        let stride = MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: length / stride + 16)
        var actual = buffer.count * stride
        guard sysctl(&name, 4, &buffer, &actual, nil, 0) == 0 else {
            return []
        }

        return (0 ..< (actual / stride)).compactMap { index in
            var entry = buffer[index]
            let command = withUnsafePointer(to: &entry.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            guard !command.isEmpty else { return nil }
            return RunningProcess(
                processIdentifier: entry.kp_proc.p_pid,
                executableName: command
            )
        }
    }
}

/// Reads live login sessions from `utmpx`, the database behind `who`.
public struct UtmpxLoginSessionEnumerator: LoginSessionEnumerating {
    public init() {}

    public func loginSessions() -> [LoginSession] {
        var sessions: [LoginSession] = []
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            var record = entry.pointee
            guard Int32(record.ut_type) == USER_PROCESS else { continue }
            let user = Self.string(from: &record.ut_user)
            let line = Self.string(from: &record.ut_line)
            let host = Self.string(from: &record.ut_host)
            guard !user.isEmpty else { continue }
            sessions.append(LoginSession(user: user, line: line, remoteHost: host))
        }
        return sessions
    }

    /// `utmpx` fields are fixed-size, NUL-padded C arrays rather than
    /// pointers, so each one has to be rebound in place.
    private static func string<Field>(from field: inout Field) -> String {
        withUnsafePointer(to: &field) {
            $0.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout<Field>.size
            ) { start in
                let bytes = UnsafeBufferPointer(start: start, count: MemoryLayout<Field>.size)
                let characters = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                // A hostname or username that is not valid UTF-8 is a
                // corrupt record, not a session to hold enforcement for, so
                // it becomes the empty string and is filtered out upstream.
                return String(bytes: characters, encoding: .utf8) ?? ""
            }
        }
    }
}

/// Sees no processes. Used by ``LiveProtectedWorkMonitor/disabled``.
public struct EmptyProcessEnumerator: RunningProcessEnumerating {
    public init() {}

    public func runningProcesses() -> [RunningProcess] {
        []
    }
}

/// Sees no sessions. Used by ``LiveProtectedWorkMonitor/disabled``.
public struct EmptyLoginSessionEnumerator: LoginSessionEnumerating {
    public init() {}

    public func loginSessions() -> [LoginSession] {
        []
    }
}
