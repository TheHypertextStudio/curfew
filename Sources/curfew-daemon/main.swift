import CurfewKit
import Foundation
import OSLog

private let daemonLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "privileged-daemon"
)

/// How long the daemon waits without seeing an app heartbeat before
/// concluding the Curfew app has been force-killed and triggering its
/// shutdown enforcement. Generous enough to absorb a LaunchAgent respawn
/// (which usually completes in a few seconds) and a fresh tick loop
/// arming itself.
private let appHeartbeatTimeout: TimeInterval = 90

/// Seconds between daemon loop iterations. 15 keeps the daemon responsive
/// to bypass attempts without burning measurable CPU; combined with
/// `appHeartbeatTimeout`, the worst-case bypass detection window is
/// roughly 90–105 seconds.
private let loopInterval: TimeInterval = 15

/// Where the privileged daemon writes its own heartbeat so the app (and
/// integration tests) can verify the daemon is alive without parsing
/// `launchctl print` output.
private let daemonHeartbeatURL = SharedPaths.privilegedApplicationSupport
    .appendingPathComponent(".daemon-alive")

private let fileManager = FileManager.default

private let remoteCommandJWKSURL = CurfewServiceEndpoints.current.remoteCommandJWKS

private let remoteCommandStateStore = DaemonRemoteCommandStateStore(
    stateURL: SharedPaths.remoteCommandState
)

/// Daemon composition root. Local MCP and remote MCP supply the same narrow
/// dependency, so enforcement policy does not know which transport produced a
/// deadline and a failure in either backend cannot suppress the other.
private let commandBackends = DaemonCommandBackendSet(backends: [
    DaemonLocalCommandBackend(
        userStore: LockoutDeadlineStore(recordURL: SharedPaths.lockoutDeadline),
        shadowStore: LockoutDeadlineStore(recordURL: SharedPaths.lockoutDeadlineShadow)
    ),
    DaemonRemoteMCPBackend(
        commandProcessor: DaemonRemoteCommandBackend(
            enrollmentStore: RemoteCommandEnrollmentStore(
                recordURL: SharedPaths.remoteCommandEnrollment
            ),
            inboxStore: RemoteCommandInboxStore(
                directoryURL: SharedPaths.remoteCommandInbox
            ),
            stateStore: remoteCommandStateStore,
            jwksProvider: HTTPRemoteCommandJWKSProvider(endpoint: remoteCommandJWKSURL)
        ),
        stateStore: remoteCommandStateStore,
        resultExchange: RemoteCommandResultExchangeStore(
            resultsURL: SharedPaths.remoteCommandResults,
            acknowledgementsDirectoryURL: SharedPaths.remoteCommandResultAcknowledgements,
            requiredDirectoryOwnerUserID: 0
        )
    )
])

/// Removes the shadow copy. Called after the deadline naturally elapses
/// so the next launch starts clean.
private func clearShadow() {
    guard fileManager.fileExists(atPath: SharedPaths.lockoutDeadlineShadow.path) else {
        return
    }
    try? fileManager.removeItem(at: SharedPaths.lockoutDeadlineShadow)
}

/// Returns the age (in seconds) of the app-heartbeat file. Missing file
/// returns `.infinity` so the daemon treats it as a hard staleness.
private func appHeartbeatAge(now: Date) -> TimeInterval {
    let url = SharedPaths.appHeartbeat
    guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
          let modified = attrs[.modificationDate] as? Date
    else {
        return .infinity
    }
    return now.timeIntervalSince(modified)
}

/// Invokes `/sbin/shutdown -h +1` as root. The `+1` gives any open
/// applications one minute to save unsaved work and surfaces a system
/// dialog the user cannot dismiss from user-space (the AppleScript
/// path the app uses can be cancelled; this one cannot).
///
/// Because it cannot be cancelled from user space, this is the command that
/// makes `killall Curfew` a trap rather than an escape. The break-glass path
/// in `curfew-ctl` is the documented way back out; see
/// `Documentation/protected-work.md`.
private func runShutdown() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/shutdown")
    process.arguments = ["-h", "+1", "Curfew enforcement: app process missing during lockout."]
    do {
        try process.run()
        daemonLogger.notice("/sbin/shutdown -h +1 issued by daemon")
    } catch {
        daemonLogger.error(
            "shutdown invocation failed: \(error.localizedDescription, privacy: .public)"
        )
        // Rethrown rather than recorded here, so `DaemonEnforcementRuntime`
        // writes one record describing what actually happened instead of an
        // `issued` line followed by a contradicting `failed` line.
        throw error
    }
}

/// Writes the daemon's own heartbeat file so external watchers can tell
/// whether the daemon is itself alive.
private func touchDaemonHeartbeat(now: Date) {
    do {
        try fileManager.createDirectory(
            at: daemonHeartbeatURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = ISO8601DateFormatter().string(from: now)
            .data(using: .utf8) ?? Data()
        try payload.write(to: daemonHeartbeatURL, options: .atomic)
    } catch {
        daemonLogger.error(
            "daemon heartbeat write failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

// MARK: - Bounded deferral, persisted across daemon restarts

/// Reads when the current deferral window opened, if one is open.
///
/// The marker lives in the root-owned privileged directory rather than in
/// memory because a daemon that restarts must not get a fresh 30 minutes.
/// `launchd` will happily respawn this process, so an in-memory clock would
/// make the bound meaningless.
///
/// Whether a marker found here still *applies* is not decided here —
/// `DaemonEnforcementDecision` drops one that predates the current lockout
/// window or is dated in the future.
private func loadDeferralStart() -> Date? {
    let url = SharedPaths.enforcementDeferralMarker
    guard let data = try? BoundedRegularFileReader.read(url, maximumBytes: 4096),
          let text = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    return ISO8601DateFormatter().date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func writeDeferralStart(_ start: Date?) {
    let url = SharedPaths.enforcementDeferralMarker
    guard let start else {
        try? fileManager.removeItem(at: url)
        return
    }
    do {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = ISO8601DateFormatter().string(from: start)
        try Data(payload.utf8).write(to: url, options: .atomic)
    } catch {
        daemonLogger.error(
            "deferral marker write failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

// MARK: - Effects

/// The real machine. Every branch that used to be inline in the loop below now
/// lives behind `DaemonEnforcementEffects`, so `DaemonEnforcementRuntime` can
/// be driven by a recording spy in tests.
private final class SystemDaemonEffects: DaemonEnforcementEffects {
    private let canceller: any PendingShutdownCanceling

    init(canceller: any PendingShutdownCanceling = SystemShutdownCanceller()) {
        self.canceller = canceller
    }

    func persistDeferralStart(_ start: Date?) {
        writeDeferralStart(start)
    }

    func cancelPendingShutdown() {
        // `/sbin/shutdown -h +1` cannot be called off from user space, which
        // is exactly why the daemon has to do it on the user's behalf.
        canceller.cancelPendingShutdown()
    }

    func issueShutdown() throws {
        try runShutdown()
    }

    func clearDeadlineShadow() {
        clearShadow()
    }
}

daemonLogger.info("curfew-daemon launched")

// The daemon writes its own audit stream at /Library/Logs/Curfew/. Separate
// file, separate hash chain: this process runs as root while the app runs as
// the user, and giving them one file would mean either a lock protocol across
// a privilege boundary or interleaved lines. Root ownership of this file is
// also what makes its chain worth having — the person being audited cannot
// rewrite it without escalating first. See `Documentation/audit-log.md`.
AuditLog.bootstrap(stream: .daemon)
AuditLog.shared.emit(
    .daemonStarted,
    actor: .daemon,
    detail: [
        "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
        "uid": .int(Int(getuid())),
        "loopIntervalSeconds": .int(Int(loopInterval)),
        "heartbeatTimeoutSeconds": .int(Int(appHeartbeatTimeout))
    ]
)

// The daemon watches the same two sources the app does — declared claims and
// the live machine — through the one type that combines them, so root's answer
// and the user's answer cannot drift. Unlike the app there is no test host to
// keep deterministic here, so liveness is on unconditionally: this process
// exists to power the Mac off, and it is the path an unclaimed agent run has no
// other defence against.
private let protectedWorkStores = ProtectedWorkStores(live: .system)
private let breakGlassStore = BreakGlassStore()
private let effects = SystemDaemonEffects()
private let observer = DaemonAuditObserver(auditLog: .shared)
var runtime = DaemonEnforcementRuntime(auditLog: .shared)

// Read the world, ask, apply, log, sleep. Nothing in this loop decides
// anything and nothing in it touches the machine directly — every judgement
// is `DaemonEnforcementDecision` and every side effect is
// `DaemonEnforcementRuntime` plus `effects`. Three review rounds found three
// bugs on this branch and all three were in loop code shaped like this one
// used to be, so keep it boring.
while true {
    let now = Date()
    touchDaemonHeartbeat(now: now)

    let backendSnapshot = commandBackends.synchronize(at: now)
    for receipt in backendSnapshot.receipts {
        daemonLogger.notice(
            "remote command \(receipt.result.commandID, privacy: .public) resolved as \(receipt.result.stage.rawValue, privacy: .public)"
        )
    }
    for failure in backendSnapshot.failures {
        daemonLogger.error(
            "\(failure.backend, privacy: .public) backend failed: \(failure.message, privacy: .public)"
        )
    }

    let record = backendSnapshot.deadline
    let breakGlass = record.flatMap { deadline in
        breakGlassStore.activeRelease(now: now, issuedAfter: deadline.lockoutStartedAt)
    }
    let heartbeatAge = appHeartbeatAge(now: now)
    // Read the mirror once: the same policy has to decide both which processes
    // count as live work and how long the resulting hold may last.
    let protectedWorkPolicy = ProtectedWorkPolicy.loadMirror()
    let liveWork = protectedWorkStores.live.observe(policy: protectedWorkPolicy)
    let hasProtectedWork = protectedWorkStores.claims.hasActiveWork(now: now)
        || liveWork.isActive

    // The loop records what it *read*; `DaemonEnforcementRuntime` records what
    // was *done* about it. Keeping the two apart means no fact is written by a
    // layer that had to guess it.
    observer.record(
        DaemonAuditObserver.Observation(
            now: now,
            deadline: record,
            deadlineCameFromUserFile: fileManager.fileExists(
                atPath: SharedPaths.lockoutDeadline.path
            ),
            heartbeatAge: heartbeatAge,
            heartbeatTimeout: appHeartbeatTimeout,
            hasActiveProtectedWork: hasProtectedWork,
            breakGlass: breakGlass
        )
    )

    let outcome = DaemonEnforcementDecision.evaluate(
        DaemonEnforcementDecision.Input(
            now: now,
            deadline: record,
            breakGlassActive: breakGlass != nil,
            heartbeatAge: heartbeatAge,
            heartbeatTimeout: appHeartbeatTimeout,
            hasActiveProtectedWork: hasProtectedWork,
            maximumDeferral: protectedWorkPolicy.maximumDeferral,
            persistedDeferralStart: loadDeferralStart(),
            shutdownAlreadyIssued: runtime.shutdownIssued
        )
    )

    switch runtime.apply(outcome, effects: effects, now: now) {
    case .exiting:
        daemonLogger.info("no lockout left to enforce; daemon exiting")
    case .standingDown:
        let id = breakGlass?.id.uuidString ?? "unknown"
        daemonLogger.notice("break-glass release \(id, privacy: .public) honored; standing down")
    case .holding(let until):
        // Name what is holding. "Protected work is live" alone sent whoever
        // was debugging this at 02:00 looking for a claim file that, for an
        // undeclared agent run, was never going to be there.
        let because = liveWork.summary.isEmpty ? "declared claim" : liveWork.summary
        daemonLogger.notice(
            """
            shutdown due but protected work is live (\(because, privacy: .public)); \
            holding until \(until, privacy: .public)
            """
        )
    case .issuedShutdown:
        daemonLogger.notice("app heartbeat stale during lockout; issued shutdown")
    case .idle:
        break
    }

    if runtime.shouldExit {
        break
    }
    // Keep looping on stand-down rather than exiting: `KeepAlive.PathState`
    // would respawn us the moment we quit, and a process that dies and returns
    // every ten seconds is worse company than one that sits quietly.
    Thread.sleep(forTimeInterval: loopInterval)
}

daemonLogger.info("curfew-daemon exiting")
AuditLog.shared.emit(
    .daemonStopped,
    actor: .daemon,
    detail: ["shutdownIssued": .bool(runtime.shutdownIssued)]
)
