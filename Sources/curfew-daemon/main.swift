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

daemonLogger.info("curfew-daemon launched")

/// True once the daemon has issued a shutdown for the current lockout
/// window. Set so the daemon doesn't fire the shutdown command twice
/// while `/sbin/shutdown -h +1` is honoring its one-minute delay.
var shutdownIssued = false

while true {
    let now = Date()
    touchDaemonHeartbeat(now: now)

    guard let record = loadDeadline() else {
        // No active lockout — daemon's job is done for this window.
        clearShadow()
        daemonLogger.info("no lockout deadline found, daemon exiting")
        break
    }

    if now >= record.scheduledUnlockAt {
        // Window elapsed naturally. Clear shadow + exit so we don't keep
        // a process alive past the legitimate unlock time.
        clearShadow()
        daemonLogger.info(
            "lockout deadline elapsed at \(record.scheduledUnlockAt, privacy: .public)"
        )
        break
    }

    let age = appHeartbeatAge(now: now)
    if age > appHeartbeatTimeout, !shutdownIssued {
        daemonLogger.notice(
            "app heartbeat stale (\(age, privacy: .public)s); issuing shutdown"
        )
        issueShutdown()
        shutdownIssued = true
    }

    Thread.sleep(forTimeInterval: loopInterval)
}

daemonLogger.info("curfew-daemon exiting")
