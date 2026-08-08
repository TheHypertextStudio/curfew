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
private func issueShutdown() {
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

private func persistDeferralStart(_ start: Date?) {
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

daemonLogger.info("curfew-daemon launched")

/// True once the daemon has issued a shutdown for the current lockout
/// window. Set so the daemon doesn't fire the shutdown command twice
/// while `/sbin/shutdown -h +1` is honoring its one-minute delay.
var shutdownIssued = false

/// True while a break-glass release is being honored, so the daemon logs and
/// cancels once rather than on every fifteen-second pass.
var breakGlassHonored = false

let protectedWorkStore = ProtectedWorkStore()
let breakGlassStore = BreakGlassStore()

// The loop is deliberately dumb: read the world, ask
// `DaemonEnforcementDecision`, do what it says, persist what it returns.
// Every judgement call lives in that pure type so it can be tested, which is
// how the stale-marker bug below was caught. Nothing here may decide anything
// on its own — least of all whether to skip a marker write.
while true {
    let now = Date()
    touchDaemonHeartbeat(now: now)

    let record = loadDeadline()
    let breakGlass = record.flatMap { deadline in
        breakGlassStore.activeRelease(now: now, issuedAfter: deadline.lockoutStartedAt)
    }

    let outcome = DaemonEnforcementDecision.evaluate(
        DaemonEnforcementDecision.Input(
            now: now,
            deadline: record,
            breakGlassActive: breakGlass != nil,
            heartbeatAge: appHeartbeatAge(now: now),
            heartbeatTimeout: appHeartbeatTimeout,
            hasActiveProtectedWork: protectedWorkStore.hasActiveWork(now: now),
            maximumDeferral: ProtectedWorkPolicy.loadMirror().maximumDeferral,
            persistedDeferralStart: loadDeferralStart(),
            shutdownAlreadyIssued: shutdownIssued
        )
    )

    // Unconditional, including nil. A heartbeat that recovers must close its
    // window here, or the next genuine incident in this same lockout inherits
    // a budget that is already spent and gets no grace at all.
    persistDeferralStart(outcome.deferralStartedAt)

    switch outcome.action {
    case .exit:
        clearShadow()
        daemonLogger.info("no lockout left to enforce; daemon exiting")

    case .standDown:
        if !breakGlassHonored {
            let id = breakGlass?.id.uuidString ?? "unknown"
            daemonLogger.notice("break-glass release \(id, privacy: .public) honored; standing down")
            // Cancel a shutdown this daemon may already have issued. Without
            // this the release would arrive too late to matter:
            // `/sbin/shutdown -h +1` cannot be called off from user space.
            SystemShutdownCanceller().cancelPendingShutdown()
            // Re-arm, so revoking the release mid-window puts enforcement back.
            shutdownIssued = false
            breakGlassHonored = true
        }

    case .hold(let until):
        breakGlassHonored = false
        daemonLogger.notice(
            "app heartbeat stale but protected work is live; holding until \(until, privacy: .public)"
        )

    case .shutDown:
        breakGlassHonored = false
        daemonLogger.notice("app heartbeat stale during lockout; issuing shutdown")
        issueShutdown()
        shutdownIssued = true

    case .wait:
        breakGlassHonored = false
    }

    if outcome.action == .exit {
        break
    }
    // Keep looping on stand-down rather than exiting: `KeepAlive.PathState`
    // would respawn us the moment we quit, and a process that dies and returns
    // every ten seconds is worse company than one that sits quietly.
    Thread.sleep(forTimeInterval: loopInterval)
}

daemonLogger.info("curfew-daemon exiting")
