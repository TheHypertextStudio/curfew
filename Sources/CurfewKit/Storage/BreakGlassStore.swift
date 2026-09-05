import CryptoKit
import Foundation
import OSLog

private let breakGlassLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "break-glass"
)

/// A recorded decision to stand root-level enforcement down for the rest of
/// the current lockout window.
///
/// Break-glass exists because the privileged daemon turns a mistake into a
/// trap. The daemon's answer to "the Curfew app stopped heartbeating during a
/// lockout" is `/sbin/shutdown -h +1`, chosen precisely because user space
/// cannot cancel it. Anyone who reaches for `killall Curfew` — to debug, to
/// recover from a crash loop, or because a background agent is mid-task — gets
/// a forced power-off a minute later, and the only surface offering to help is
/// behind a locked display.
///
/// So there has to be a release that does not depend on the display: one
/// command, from any terminal or over SSH, that stops the pending shutdown and
/// tells the daemon to stand down. That is this record.
///
/// It is not a security boundary. The signing key sits in the user's own
/// Application Support directory, and anybody who can read it can already run
/// `sudo`. What the signature buys is that a stray write, a stale file from a
/// previous install, or a buggy script cannot disable root-level enforcement
/// by accident — releasing has to be something a person meant to do.
public struct BreakGlassRelease: Codable, Equatable, Identifiable, Sendable {
    /// Stable key for the release, logged so the event is traceable.
    public let id: UUID

    /// When the release was issued.
    public let issuedAt: Date

    /// Why. Required, and required to be substantial — see
    /// ``BreakGlassStore/minimumReasonCharacters``. The friction is the point:
    /// a commitment device whose escape hatch costs nothing is not a
    /// commitment device.
    public let reason: String

    /// `user@host` of whoever issued it, captured for the audit trail.
    public let issuedBy: String

    /// Hex-encoded HMAC-SHA256 over the fields above. Absent means unsigned,
    /// which every consumer treats as invalid.
    public var signature: String?

    public init(
        id: UUID = UUID(),
        issuedAt: Date,
        reason: String,
        issuedBy: String,
        signature: String? = nil
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.reason = reason
        self.issuedBy = issuedBy
        self.signature = signature
    }
}

/// Why a break-glass attempt was refused.
public enum BreakGlassError: Error, LocalizedError, Equatable {
    /// The supplied reason was shorter than ``BreakGlassStore/minimumReasonCharacters``.
    case reasonTooShort(minimum: Int)

    /// The signing key could not be read or created.
    case signingUnavailable

    /// The record could not be written.
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .reasonTooShort(let minimum):
            "Break-glass needs a reason of at least \(minimum) characters."
        case .signingUnavailable:
            "Could not read or create the break-glass signing key."
        case .writeFailed(let message):
            "Could not write the break-glass record: \(message)."
        }
    }
}

/// Signs and verifies ``BreakGlassRelease`` records with a per-install
/// symmetric key, mirroring ``MCPRequestSigner`` so there is one signing
/// pattern in the codebase rather than two.
public enum BreakGlassSigner {
    /// Hex-encoded HMAC-SHA256 of `{id}|{issuedAt-ISO}|{reason}|{issuedBy}`,
    /// or `nil` when the key is unavailable.
    public static func sign(
        _ release: BreakGlassRelease,
        secretURL: URL = SharedPaths.breakGlassSecret
    ) -> String? {
        guard let key = loadOrCreateSecret(at: secretURL),
              let data = canonicalString(for: release).data(using: .utf8)
        else {
            return nil
        }
        return HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Whether `release.signature` matches the canonical payload. Missing
    /// signature, missing key, and mismatch all return `false` — the call
    /// sites treat them identically (do not stand enforcement down).
    public static func verify(
        _ release: BreakGlassRelease,
        secretURL: URL = SharedPaths.breakGlassSecret
    ) -> Bool {
        guard let signature = release.signature,
              let key = loadOrCreateSecret(at: secretURL),
              let signatureData = Data(breakGlassHex: signature),
              let payload = canonicalString(for: release).data(using: .utf8)
        else {
            return false
        }
        return HMAC<SHA256>.isValidAuthenticationCode(
            signatureData,
            authenticating: payload,
            using: key
        )
    }

    /// Wire contract for the signature. Order and separators are load-bearing:
    /// changing either invalidates every record already on disk.
    private static func canonicalString(for release: BreakGlassRelease) -> String {
        let timestamp = ISO8601DateFormatter.curfewBreakGlass.string(from: release.issuedAt)
        return [
            release.id.uuidString,
            timestamp,
            release.reason,
            release.issuedBy
        ].joined(separator: "|")
    }

    private static func loadOrCreateSecret(at url: URL) -> SymmetricKey? {
        let fileManager = FileManager.default
        if let data = try? BoundedRegularFileReader.read(url, maximumBytes: 32),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let key = SymmetricKey(size: .bits256)
            try key.withUnsafeBytes { Data($0) }.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: url.path
            )
            breakGlassLogger.info("generated new break-glass secret")
            return key
        } catch {
            breakGlassLogger.error(
                "failed to provision break-glass secret: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}

/// Atomic JSON store for the break-glass record at
/// ``SharedPaths/breakGlassRelease``.
public struct BreakGlassStore {
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
        now: Date
    ) throws -> BreakGlassRelease {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumReasonCharacters else {
            throw BreakGlassError.reasonTooShort(minimum: Self.minimumReasonCharacters)
        }

        var release = BreakGlassRelease(
            issuedAt: now,
            reason: trimmed,
            issuedBy: issuedBy
        )
        guard let signature = BreakGlassSigner.sign(release, secretURL: secretURL) else {
            throw BreakGlassError.signingUnavailable
        }
        release.signature = signature

        do {
            try fileManager.createDirectory(
                at: recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(release).write(to: recordURL, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: recordURL.path
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
            maximumBytes: 65536
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
        if let issuedAfter, release.issuedAt < issuedAfter {
            return nil
        }
        guard now.timeIntervalSince(release.issuedAt) <= validity else {
            return nil
        }
        return release
    }

    /// Removes the record. Called when a lockout window ends so the next one
    /// is enforced normally.
    public func clear() {
        guard fileManager.fileExists(atPath: recordURL.path) else { return }
        try? fileManager.removeItem(at: recordURL)
    }
}

// MARK: - Cancelling a shutdown that is already in flight

/// Stops a `/sbin/shutdown` that the daemon has already issued.
///
/// Split behind a protocol so the break-glass path is testable without a
/// machine that actually powers off.
public protocol PendingShutdownCanceling: Sendable {
    /// Terminates any pending `shutdown` process. Returns `true` when at least
    /// one was signalled.
    @discardableResult
    func cancelPendingShutdown() -> Bool
}

/// Production canceller. `/sbin/shutdown -h +1` has no cancel flag on macOS,
/// so the only way back is to kill the waiting process — which needs root,
/// hence the `sudo curfew-ctl break-glass` form in the runbook.
public struct SystemShutdownCanceller: PendingShutdownCanceling {
    public init() {}

    @discardableResult
    public func cancelPendingShutdown() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "shutdown"]
        do {
            try process.run()
            process.waitUntilExit()
            // pkill exits 0 when it signalled something, 1 when it matched
            // nothing. Nothing to kill is a normal outcome, not a failure.
            return process.terminationStatus == 0
        } catch {
            breakGlassLogger.error(
                "failed to cancel pending shutdown: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}

// MARK: - Private helpers

private extension ISO8601DateFormatter {
    /// Single formatter reused across sign and verify so the wire string is
    /// stable. Fractional seconds are excluded on purpose — they would not
    /// survive the JSON round-trip identically.
    static let curfewBreakGlass: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension Data {
    /// Parses a hex string into bytes, failing closed on any non-hex input.
    init?(breakGlassHex string: String) {
        let cleaned = string.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(after: index)
            guard let byte = UInt8(String(cleaned[index ... next]), radix: 16) else { return nil }
            bytes.append(byte)
            index = cleaned.index(after: next)
        }
        self.init(bytes)
    }
}
