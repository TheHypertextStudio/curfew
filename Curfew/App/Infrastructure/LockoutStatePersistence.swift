import CurfewKit
import Foundation
import OSLog

private let persistenceLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "lockout-state"
)

/// Writes and deletes the lockout-active sentinel file at
/// `SharedPaths.lockoutActiveSentinel` so the privileged daemon can track
/// lockout state without IPC.
///
/// When the file exists the daemon (running as root via `SMAppService`) keeps
/// itself alive via `KeepAlive.PathState`. When the file is deleted the daemon
/// exits, completing the cleanup lifecycle for that lockout session.
///
/// Write path: `locked` transition → `markLockoutActive()`.
/// Delete path: `locked → working|dayOff` transition → `markLockoutInactive()`.
///
/// Failure modes are logged and swallowed. A missing sentinel file means the
/// daemon stays dormant — the consequence is weaker enforcement, not a crash.
struct LockoutStatePersistence {
    let fileManager: FileManager
    let sentinelURL: URL

    init(
        fileManager: FileManager = .default,
        sentinelURL: URL = SharedPaths.lockoutActiveSentinel
    ) {
        self.fileManager = fileManager
        self.sentinelURL = sentinelURL
    }

    /// Creates the sentinel file at the privileged path. No-ops if the parent
    /// directory doesn't exist yet (daemon not yet installed).
    func markLockoutActive() {
        let directory = sentinelURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else {
            // Privileged directory not yet created — daemon not installed.
            return
        }
        do {
            try Data().write(to: sentinelURL, options: .atomic)
            persistenceLogger.info("lockout sentinel created")
        } catch {
            persistenceLogger.error(
                "failed to create lockout sentinel: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Removes the sentinel file, causing the daemon to exit via
    /// `KeepAlive.PathState`. Safe to call when the file does not exist.
    func markLockoutInactive() {
        guard fileManager.fileExists(atPath: sentinelURL.path) else { return }
        do {
            try fileManager.removeItem(at: sentinelURL)
            persistenceLogger.info("lockout sentinel removed")
        } catch {
            persistenceLogger.error(
                "failed to remove lockout sentinel: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func markLockoutActive() {
        LockoutStatePersistence().markLockoutActive()
    }

    static func markLockoutInactive() {
        LockoutStatePersistence().markLockoutInactive()
    }
}
