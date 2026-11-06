import Foundation
import OSLog

private let breakGlassLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "break-glass"
)

/// A recorded decision to stand root-level enforcement down for the rest of
/// the current lockout window.
///
/// The daemon schedules `/sbin/shutdown -h +1` if Curfew stops heartbeating
/// during lockout. User space cannot cancel that shutdown, so emergency
/// recovery must work from a terminal or SSH while the display is locked.
/// This record lets an intentional release stop the pending shutdown and
/// tell the daemon to stand down.
///
/// HMAC detects unintended or stale writes; its key lives in the user's Application Support.
public struct BreakGlassRelease: Codable, Equatable, Identifiable, Sendable {
    /// Stable key for the release, logged so the event is traceable.
    public let id: UUID

    /// When the release was issued.
    public let issuedAt: Date

    /// Required explanation, at least ``BreakGlassStore/minimumReasonCharacters``
    /// characters, so emergency release remains an intentional decision.
    public let reason: String

    /// `user@host` of whoever issued it, captured for the audit trail.
    public let issuedBy: String

    /// Optional tighter expiry used by coordinator-authorized releases. A
    /// missing value preserves the legacy per-window/default-validity rules.
    public let expiresAt: Date?

    /// Hex-encoded HMAC-SHA256 over the fields above. Absent means unsigned,
    /// which every consumer treats as invalid.
    public var signature: String?

    public init(
        id: UUID = UUID(),
        issuedAt: Date,
        reason: String,
        issuedBy: String,
        expiresAt: Date? = nil,
        signature: String? = nil
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.reason = reason
        self.issuedBy = issuedBy
        self.expiresAt = expiresAt
        self.signature = signature
    }
}

/// Why a break-glass attempt was refused.
public enum BreakGlassError: Error, LocalizedError, Equatable {
    /// The supplied reason was shorter than ``BreakGlassStore/minimumReasonCharacters``.
    case reasonTooShort(minimum: Int)

    /// The signing key could not be read or created.
    case signingUnavailable

    /// The encoded record exceeds the bound enforced by readers.
    case recordTooLarge(maximumBytes: Int)

    /// The record could not be written.
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .reasonTooShort(let minimum):
            "Break-glass needs a reason of at least \(minimum) characters."
        case .signingUnavailable:
            "Could not read or create the break-glass signing key."
        case .recordTooLarge(let maximumBytes):
            "The break-glass record exceeds \(maximumBytes) encoded bytes. Shorten the reason or issuer."
        case .writeFailed(let message):
            "Could not write the break-glass record: \(message)."
        }
    }
}

/// Atomic JSON store for the break-glass record at
/// ``SharedPaths/breakGlassRelease``.
public struct BreakGlassStore {
    private static let maximumRecordBytes = 65536

    /// Shortest reason the CLI will accept. Long enough that the user has to
    /// articulate what went wrong, short enough to type one-handed at 23:00.
    public static let minimumReasonCharacters = 20

    /// How long a verified record stays honored when the caller cannot tell
    /// the store when the current lockout began. Twelve hours covers a night
    /// and expires before the next one, so a forgotten record cannot quietly
    /// disable every future lockout.
    public static let defaultValidity: TimeInterval = 12 * 60 * 60

    private let fileManager: FileManager

    /// Where the record lives. Exposed for tests.
    public let recordURL: URL

    /// Where the signing key lives. Exposed for tests.
    public let secretURL: URL

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
        recordURL: URL = SharedPaths.breakGlassRelease,
        secretURL: URL = SharedPaths.breakGlassSecret
    ) {
        self.fileManager = fileManager
        self.recordURL = recordURL
        self.secretURL = secretURL
    }

    /// Writes a signed release. Rejects a thin reason before touching disk.
    @discardableResult
    public func issue(
        reason: String,
        issuedBy: String,
        now: Date,
        expiresAt: Date? = nil
    ) throws -> BreakGlassRelease {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumReasonCharacters else {
            throw BreakGlassError.reasonTooShort(minimum: Self.minimumReasonCharacters)
        }

        var release = BreakGlassRelease(
            issuedAt: now,
            reason: trimmed,
            issuedBy: issuedBy,
            expiresAt: expiresAt
        )
        // Sign the dates consumers reload. ISO8601DateFormatter can round a
        // submillisecond boundary up while JSONEncoder's ISO8601 storage truncates it.
        do {
            release = try decoder.decode(BreakGlassRelease.self, from: encoder.encode(release))
        } catch {
            throw BreakGlassError.writeFailed(error.localizedDescription)
        }
        guard let signature = BreakGlassSigner.sign(release, secretURL: secretURL) else {
            throw BreakGlassError.signingUnavailable
        }
        release.signature = signature

        let data = try encoder.encode(release)
        guard data.count <= Self.maximumRecordBytes else {
            throw BreakGlassError.recordTooLarge(maximumBytes: Self.maximumRecordBytes)
        }
        do {
            try fileManager.createDirectory(
                at: recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try BreakGlassPrivateFileWriter.write(
                data, to: recordURL, replaceExisting: true
            )
        } catch {
            throw BreakGlassError.writeFailed(error.localizedDescription)
        }

        breakGlassLogger.notice(
            "break-glass issued \(release.id.uuidString, privacy: .public) by \(issuedBy, privacy: .public)"
        )
        return release
    }

    /// Reads the record without checking it.
    public func load() -> BreakGlassRelease? {
        guard let data = try? BoundedRegularFileReader.read(
                  recordURL,
                  maximumBytes: Self.maximumRecordBytes
              ),
              let release = try? decoder.decode(BreakGlassRelease.self, from: data)
        else {
            return nil
        }
        return release
    }

    /// The record, if there is one that enforcement must honor right now.
    ///
    /// A record counts only when its signature verifies, it was not issued in
    /// the future, and it belongs to the window being enforced. `issuedAfter`
    /// carries the current lockout's start where the caller knows it (the
    /// daemon does, from the deadline record); without it the record ages out
    /// after `validity`. Both rules exist to stop last Tuesday's release from
    /// applying to tonight.
    public func activeRelease(
        now: Date,
        issuedAfter: Date? = nil,
        validity: TimeInterval = BreakGlassStore.defaultValidity
    ) -> BreakGlassRelease? {
        guard let release = load() else {
            return nil
        }
        guard BreakGlassSigner.verify(release, secretURL: secretURL) else {
            breakGlassLogger.error("break-glass record present but signature did not verify")
            return nil
        }
        guard release.issuedAt <= now else {
            breakGlassLogger.error("break-glass record is dated in the future; ignoring")
            return nil
        }
        if let expiresAt = release.expiresAt,
           now >= expiresAt {
            return nil
        }
        if let issuedAfter, release.issuedAt < issuedAfter {
            return nil
        }
        guard now.timeIntervalSince(release.issuedAt) <= validity else {
            return nil
        }
        return release
    }

    /// Returns an active coordinator-issued release without binding it to the
    /// lockout's start time. A direct-unlock grant may legitimately begin
    /// before the lock it releases, so its signed exact expiry is the bound.
    public func activeCoordinatorRelease(now: Date) -> BreakGlassRelease? {
        guard let release = activeRelease(now: now, validity: .infinity),
              release.issuedBy == "remote-mcp@curfew",
              let expiresAt = release.expiresAt,
              expiresAt > release.issuedAt
        else { return nil }
        return release
    }

    /// Removes a release at the user's request. A missing record is already
    /// revoked; every other removal failure must reach the caller.
    public func revoke() throws {
        do {
            try fileManager.removeItem(at: recordURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// Removes the record. Called when a lockout window ends so the next one
    /// is enforced normally.
    public func clear() {
        guard fileManager.fileExists(atPath: recordURL.path) else { return }
        try? fileManager.removeItem(at: recordURL)
    }
}
