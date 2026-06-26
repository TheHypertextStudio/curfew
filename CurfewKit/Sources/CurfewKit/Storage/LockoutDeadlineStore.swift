import Foundation
import OSLog

private let lockoutDeadlineLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "lockout-deadline"
)

/// Origin tag for a durable lockout-deadline record. Carries enough
/// metadata that the lockout screen, activity log, and any future
/// remote-state surface can describe *why* the device is held without
/// having to inspect the schedule that produced the original lock.
public enum LockoutKind: String, Codable, Equatable {
    /// Wall-clock schedule fired (`.time` mode or `.combined` with the
    /// time deadline winning).
    case scheduledTime = "scheduled_time"
    /// Hours-of-work budget fired (`.hours` mode or `.combined` with the
    /// hours deadline winning).
    case scheduledHours = "scheduled_hours"
}

/// Authoritative lockout-deadline record persisted to disk so that:
///
/// 1. A force-shutdown or crash mid-lockout still leaves enforcement
///    armed at the next launch (M5 in the v0.1 audit).
/// 2. The app, the privileged daemon (when wired), and any out-of-process
///    consumer share one source of truth for "are we currently locked,
///    and until when?" (A1 in the audit).
///
/// The record stays alive for the duration of one lockout window. It is
/// written on `.locked` entry, deleted on natural unlock (when
/// `Date() >= scheduledUnlockAt`), and refused-to-delete in any other
/// path. A user with shell access can tamper with the file, but doing so
/// is no easier than killing the app process — once the privileged
/// daemon's enforcement landing zone is implemented (C3/C4), the daemon
/// owns the file and the user no longer needs to read it.
public struct LockoutDeadlineRecord: Codable, Equatable {
    /// Moment the lockout window opened. Carried for activity-log
    /// attribution; not used in apply-time decisions.
    public var lockoutStartedAt: Date

    /// Moment the lockout window naturally ends. The model and the
    /// daemon both treat this as the authoritative "are we still locked"
    /// boundary — schedule re-evaluation cannot release the lockout
    /// while `Date() < scheduledUnlockAt`.
    public var scheduledUnlockAt: Date

    /// What caused this lockout. See ``LockoutKind``.
    public var kind: LockoutKind

    public init(
        lockoutStartedAt: Date,
        scheduledUnlockAt: Date,
        kind: LockoutKind
    ) {
        self.lockoutStartedAt = lockoutStartedAt
        self.scheduledUnlockAt = scheduledUnlockAt
        self.kind = kind
    }
}

/// Atomic JSON store for ``LockoutDeadlineRecord``.
///
/// Lives in the user's shared support directory today; the v0.2 daemon
/// will relocate (or shadow) it into `/Library/Application Support/Curfew`
/// so root ownership protects the file from the same user who's trying
/// to bypass enforcement. The file format is forward-compatible: callers
/// that find a malformed payload treat the record as absent and proceed
/// without forcing a lockout — fail-open at the storage boundary is the
/// right default because corrupt durable state must not hold a user
/// captive past their actual unlock time.
public struct LockoutDeadlineStore {
    private let fileManager: FileManager
    /// Where the record lives on disk. Exposed for tests; production
    /// resolves it from ``SharedPaths``.
    public let recordURL: URL

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    public init(
        fileManager: FileManager = .default,
        recordURL: URL = SharedPaths.lockoutDeadline
    ) {
        self.fileManager = fileManager
        self.recordURL = recordURL
    }

    /// Reads the record from disk. Returns `nil` when the file is
    /// absent, unreadable, or fails to decode — every absence path
    /// fails open so a tampered/corrupted record doesn't hold the user
    /// past their unlock time.
    public func load() -> LockoutDeadlineRecord? {
        guard fileManager.fileExists(atPath: recordURL.path),
              let data = try? Data(contentsOf: recordURL),
              let record = try? decoder.decode(LockoutDeadlineRecord.self, from: data)
        else {
            return nil
        }
        return record
    }

    /// Writes (overwriting) the record. Atomic write so a crash mid-
    /// write can't leave a half-decoded JSON on disk.
    public func save(_ record: LockoutDeadlineRecord) {
        do {
            try fileManager.createDirectory(
                at: recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(record)
            try data.write(to: recordURL, options: .atomic)
            lockoutDeadlineLogger.info(
                "lockout-deadline saved (until: \(record.scheduledUnlockAt, privacy: .public))"
            )
        } catch {
            lockoutDeadlineLogger.error(
                "failed to save lockout-deadline: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Removes the record if present. Safe to call when absent — the
    /// guard short-circuits before any filesystem call.
    public func clear() {
        guard fileManager.fileExists(atPath: recordURL.path) else { return }
        do {
            try fileManager.removeItem(at: recordURL)
            lockoutDeadlineLogger.info("lockout-deadline cleared")
        } catch {
            lockoutDeadlineLogger.error(
                "failed to clear lockout-deadline: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
