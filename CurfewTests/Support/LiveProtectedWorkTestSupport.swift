@testable import Curfew
import Foundation
import Testing

/// A genuinely running process, spawned under a chosen executable name so the
/// allowlist has something real to match.
///
/// The carve-out's whole claim is about processes that exist, so the tests that
/// matter here refuse to settle for a fixture: they copy a real binary to a
/// chosen name, exec it, and read it back out of the kernel's own process
/// table. `p_comm` is taken from the executable's file name, which is why the
/// copy is necessary — `posix_spawn` with a rewritten `argv[0]` would not
/// change what `sysctl` reports.
final class SpawnedProcessProbe {
    /// The name the process is running under, as `p_comm` will report it.
    let executableName: String

    /// The live pid.
    var processIdentifier: Int32 {
        process.processIdentifier
    }

    private let process = Process()
    private let directory: URL

    /// Spawns a long-lived process named `executableName`.
    ///
    /// - Parameters:
    ///   - executableName: at most `MAXCOMLEN` (16) characters, or the kernel
    ///     will truncate it and the caller's expectations with it.
    ///   - lifetimeSeconds: generous enough that the process cannot exit
    ///     mid-assertion on a loaded machine.
    init(executableName: String, lifetimeSeconds: Int = 120) throws {
        self.executableName = executableName
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // `/bin/sleep` is small, signed, and does exactly one thing. Copying it
        // keeps the signature intact (the bytes are unchanged); only the name
        // the kernel records for it changes.
        let executable = directory.appendingPathComponent(executableName)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/sleep"),
            to: executable
        )

        process.executableURL = executable
        process.arguments = ["\(lifetimeSeconds)"]
        try process.run()

        // `Process.run()` returns before the exec has necessarily landed in the
        // process table. Poll rather than sleep a fixed amount, so the test is
        // neither flaky on a loaded machine nor slow on an idle one.
        try waitUntilVisible()
    }

    /// Ends the process and removes the copied binary.
    func terminateAndWait() {
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Whether the real `sysctl` reader can currently see this exact pid under
    /// this exact name.
    func isVisibleToEnumerator(_ enumerator: RunningProcessEnumerating) -> Bool {
        enumerator.runningProcesses().contains {
            $0.processIdentifier == processIdentifier && $0.executableName == executableName
        }
    }

    private func waitUntilVisible() throws {
        let enumerator = SysctlProcessEnumerator()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isVisibleToEnumerator(enumerator) {
                return
            }
            usleep(20000)
        }
        throw ProbeFailure.neverAppearedInProcessTable(executableName)
    }

    enum ProbeFailure: Error {
        case neverAppearedInProcessTable(String)
    }
}

/// The real `sysctl` reader, narrowed to processes this test spawned.
///
/// The machine a Curfew developer runs this suite on is, with some irony, the
/// machine most likely to have a real `claude` on it — three of them, when this
/// was written. A test asserting that an *unlisted* process still gets the Mac
/// shut down would then fail for a completely correct reason, and a test
/// asserting that a hold *releases* would never see it release.
///
/// Filtering by pid keeps the thing under test real — this is
/// ``SysctlProcessEnumerator`` reading the live kernel table, not a fixture —
/// while making the answer depend only on processes the test controls.
struct ScopedProcessEnumerator: RunningProcessEnumerating {
    var pids: Set<Int32>
    var underlying: RunningProcessEnumerating = SysctlProcessEnumerator()

    func runningProcesses() -> [RunningProcess] {
        underlying.runningProcesses().filter { pids.contains($0.processIdentifier) }
    }
}

/// Serves a fixed process list, for the matching rule's own tests.
struct StubProcessEnumerator: RunningProcessEnumerating {
    var processes: [RunningProcess]

    func runningProcesses() -> [RunningProcess] {
        processes
    }
}

/// Serves a fixed session list.
struct StubLoginSessionEnumerator: LoginSessionEnumerating {
    var sessions: [LoginSession]

    func loginSessions() -> [LoginSession] {
        sessions
    }
}

extension LoginSession {
    /// A session shaped like the `utmpx` record macOS writes when someone
    /// SSHes in: a real user, a pty, and a non-empty originating host.
    static func ssh(
        user: String = "willie",
        line: String = "ttys004",
        from host: String = "studio.local"
    ) -> LoginSession {
        LoginSession(user: user, line: line, remoteHost: host)
    }

    /// A session at the machine's own keyboard — `ut_host` empty.
    static func console(user: String = "willie", line: String = "console") -> LoginSession {
        LoginSession(user: user, line: line, remoteHost: "")
    }
}
