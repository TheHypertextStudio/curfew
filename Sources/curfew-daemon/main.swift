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

private let encoder: JSONEncoder = {
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = [.sortedKeys]
    return enc
}()

private let decoder: JSONDecoder = {
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return dec
}()

/// Reads the user-side deadline JSON, falling back to the daemon's
/// shadow copy when the user file is absent (deleted or never written).
/// The shadow is authoritative once a record has been observed.
private func loadDeadline() -> LockoutDeadlineRecord? {
    let userURL = SharedPaths.lockoutDeadline
    let shadowURL = SharedPaths.lockoutDeadlineShadow
    if fileManager.fileExists(atPath: userURL.path),
       let data = try? Data(contentsOf: userURL),
       let record = try? decoder.decode(LockoutDeadlineRecord.self, from: data) {
        // Refresh the shadow so the daemon's view survives if the user
        // deletes the user-side file mid-lockout.
        writeShadow(record)
        return record
    }
    if fileManager.fileExists(atPath: shadowURL.path),
       let data = try? Data(contentsOf: shadowURL),
       let record = try? decoder.decode(LockoutDeadlineRecord.self, from: data) {
        return record
    }
    return nil
}

/// Persists `record` to the shadow copy so the daemon can recover it
/// even if the user-writable original disappears.
private func writeShadow(_ record: LockoutDeadlineRecord) {
    do {
        try fileManager.createDirectory(
            at: SharedPaths.lockoutDeadlineShadow.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(record)
        try data.write(to: SharedPaths.lockoutDeadlineShadow, options: .atomic)
    } catch {
        daemonLogger.error(
            "shadow write failed: \(error.localizedDescription, privacy: .public)"
        )
    }
}

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
private func runShutdown() {
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
        // `DaemonEnforcementRuntime` already recorded `daemon.shutdown_issued`
        // for this tick. Only the launch failure is visible from here, so the
        // pair reads "commanded, then failed to start".
        AuditLog.shared.emit(
            .daemonShutdownFailed,
            actor: .daemon,
            detail: ["error": .string(error.localizedDescription)]
        )
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
    guard fileManager.fileExists(atPath: url.path),
          let text = try? String(contentsOf: url, encoding: .utf8)
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

// MARK: - Audit observations

/// Writes the audit records for what this tick *observed*, before anything is
/// decided or done about it.
///
/// Split from the decision and from `DaemonEnforcementRuntime` on purpose.
/// These are readings — a deadline file, a heartbeat mtime, a claims file, a
/// break-glass record — and they are the inputs an auditor needs in order to
/// judge whether the action that followed was warranted. Every one is
/// deduplicated on its value, because the loop runs every fifteen seconds and
/// a steady night must not produce five thousand identical lines.
private func recordObservations(
    now: Date,
    record: LockoutDeadlineRecord?,
    heartbeatAge: TimeInterval,
    hasProtectedWork: Bool,
    breakGlass: BreakGlassRelease?
) {
    let log = AuditLog.shared

    if let record {
        log.emitIfChanged(
            key: "deadline",
            to: String(record.scheduledUnlockAt.timeIntervalSince1970),
            event: .daemonDeadlineObserved,
            actor: .daemon,
            detail: [
                "lockoutStartedAt": .string(AuditTimestamp.string(from: record.lockoutStartedAt)),
                "scheduledUnlockAt": .string(
                    AuditTimestamp.string(from: record.scheduledUnlockAt)
                ),
                "kind": .string(record.kind.rawValue),
                // Which copy answered. `shadow` means the user-writable file
                // was gone and the root-owned one carried the window — someone
                // deleted the record mid-lockout.
                "source": .string(
                    fileManager.fileExists(atPath: SharedPaths.lockoutDeadline.path)
                        ? "user"
                        : "shadow"
                )
            ],
            at: now
        )
        if now >= record.scheduledUnlockAt {
            log.emitIfChanged(
                key: "deadlineElapsed",
                to: String(record.scheduledUnlockAt.timeIntervalSince1970),
                event: .daemonDeadlineElapsed,
                actor: .daemon,
                detail: [
                    "scheduledUnlockAt": .string(
                        AuditTimestamp.string(from: record.scheduledUnlockAt)
                    )
                ],
                at: now
            )
        }
    }

    let isStale = heartbeatAge > appHeartbeatTimeout
    log.emitIfChanged(
        key: "heartbeat",
        to: isStale ? "stale" : "fresh",
        event: isStale ? .daemonHeartbeatStale : .daemonHeartbeatRecovered,
        actor: .daemon,
        detail: [
            // A missing heartbeat file reads as infinite age; -1 keeps the
            // field an integer instead of a JSON `null` a parser would have to
            // special-case.
            "ageSeconds": .int(heartbeatAge.isFinite ? Int(heartbeatAge) : -1),
            "thresholdSeconds": .int(Int(appHeartbeatTimeout)),
            "heartbeatPresent": .bool(heartbeatAge.isFinite)
        ],
        at: now
    )

    log.emitIfChanged(
        key: "protectedWork",
        to: hasProtectedWork ? "active" : "none",
        event: hasProtectedWork ? .protectedWorkActive : .protectedWorkCleared,
        actor: .daemon,
        at: now
    )

    if let breakGlass {
        log.emitIfChanged(
            key: "breakGlass",
            to: breakGlass.id.uuidString,
            event: .breakGlassObserved,
            actor: .daemon,
            detail: [
                "releaseId": .string(breakGlass.id.uuidString),
                "issuedAt": .string(AuditTimestamp.string(from: breakGlass.issuedAt))
            ],
            at: now
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

    func issueShutdown() {
        runShutdown()
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

private let protectedWorkStore = ProtectedWorkStore()
private let breakGlassStore = BreakGlassStore()
private let effects = SystemDaemonEffects()
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

    let record = loadDeadline()
    let breakGlass = record.flatMap { deadline in
        breakGlassStore.activeRelease(now: now, issuedAfter: deadline.lockoutStartedAt)
    }
    let heartbeatAge = appHeartbeatAge(now: now)
    let hasProtectedWork = protectedWorkStore.hasActiveWork(now: now)

    // The loop records what it *read*; `DaemonEnforcementRuntime` records what
    // was *done* about it. Keeping the two apart means no fact is written by a
    // layer that had to guess it.
    recordObservations(
        now: now,
        record: record,
        heartbeatAge: heartbeatAge,
        hasProtectedWork: hasProtectedWork,
        breakGlass: breakGlass
    )

    let outcome = DaemonEnforcementDecision.evaluate(
        DaemonEnforcementDecision.Input(
            now: now,
            deadline: record,
            breakGlassActive: breakGlass != nil,
            heartbeatAge: heartbeatAge,
            heartbeatTimeout: appHeartbeatTimeout,
            hasActiveProtectedWork: hasProtectedWork,
            maximumDeferral: ProtectedWorkPolicy.loadMirror().maximumDeferral,
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
        daemonLogger.notice(
            "shutdown due but protected work is live; holding until \(until, privacy: .public)"
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
