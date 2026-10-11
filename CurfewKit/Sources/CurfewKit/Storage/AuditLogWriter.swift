import Foundation
import OSLog

private let auditWriterLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "audit-log"
)

/// The seam every audit emitter writes through.
///
/// Exists so the app can hold a non-optional log at all times and so tests can
/// capture records without touching the filesystem, exactly as
/// `ActivityRecording` does for the SQLite activity store.
public protocol AuditLogWriting: AnyObject {
    /// Appends one record. Must never throw and must never block the caller
    /// on anything slower than a single `write(2)`: an audit line that cannot
    /// be written is a diagnostic loss, and stalling the 1 Hz enforcement tick
    /// over one would be a far worse failure than a missing line.
    func append(_ record: AuditRecord)
}

/// Append-only JSON Lines writer for one audit stream.
///
/// **Why one file per writer.** The Curfew app runs as the user and
/// `curfew-daemon` runs as root, and both need to record during the same
/// lockout. Giving them separate files removes the interleaving problem
/// outright, costs nothing to read back (`cat`, sort by `ts`), and avoids
/// inventing a cross-privilege lock protocol that could not be tested on a
/// developer machine without installing the daemon. It is also the only
/// arrangement in which the per-stream hash chain means anything, since a
/// chain requires a single writer.
///
/// **Why the file descriptor stays open.** The writer opens once with
/// `O_APPEND` and issues a single `write(2)` per record. `O_APPEND` makes the
/// seek-and-write atomic with respect to the file offset, so even a stray
/// second writer appending short lines cannot corrupt an existing one — it
/// would only break the chain, which is exactly what the chain is for.
public final class AuditLogWriter: AuditLogWriting, @unchecked Sendable {
    /// Stream identity stamped on every record this writer emits.
    public let stream: AuditStream

    private let directory: URL
    private let baseName: String
    private let policy: AuditRotationPolicy
    private let filePermissions: Int16

    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var bytesWritten = 0
    private var lastHash: String
    private var nextSequence: Int
    /// Set when the writer could not recover the previous chain head from an
    /// existing file, so the `audit.stream_opened` record can say so.
    private var chainRecovered: Bool

    /// Opens (or creates) the active segment for `stream`.
    ///
    /// - Parameters:
    ///   - stream: Which stream this writer owns.
    ///   - directory: Override for the on-disk location. Tests pass a temp
    ///     directory; production takes the ``AuditLogPaths`` default.
    ///   - baseName: Override for the file-name stem.
    ///   - policy: Rotation and retention settings.
    ///   - filePermissions: POSIX mode for the segment files. The app stream
    ///     is `0o600` because it is the user's own record; the daemon stream
    ///     is `0o644` so the user can read what root did to their machine
    ///     without needing `sudo` to do it.
    /// - Throws: When the directory cannot be created or the file cannot be
    ///   opened for appending.
    public init(
        stream: AuditStream,
        directory: URL? = nil,
        baseName: String? = nil,
        policy: AuditRotationPolicy = .standard,
        filePermissions: Int16? = nil
    ) throws {
        self.stream = stream
        self.directory = directory ?? AuditLogPaths.directory(for: stream)
        self.baseName = baseName ?? AuditLogPaths.baseName(for: stream)
        self.policy = policy
        self.filePermissions = filePermissions ?? (stream == .daemon ? 0o644 : 0o600)
        self.lastHash = auditGenesisHash
        self.nextSequence = 1
        self.chainRecovered = false

        try FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: stream == .daemon ? 0o755 : 0o700)]
        )
        recoverChainHead()
        try openDescriptor()
    }

    deinit {
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// Path to the active segment.
    public var activeFileURL: URL {
        directory.appendingPathComponent(baseName + ".jsonl")
    }

    /// Path to rotated segment `index` (1 is the most recently rotated).
    public func rotatedFileURL(index: Int) -> URL {
        directory.appendingPathComponent("\(baseName).\(index).jsonl")
    }

    /// The hash the next appended record will carry as its `prev`.
    public var currentChainHead: String {
        lock.lock()
        defer { lock.unlock() }
        return lastHash
    }

    /// Writes the `audit.stream_opened` record describing this writer's
    /// configuration. Separated from `init` so a caller can decide whether a
    /// short-lived process is worth a marker; the app and the daemon both
    /// call it immediately after construction.
    public func recordStreamOpened(at timestamp: Date = Date()) {
        append(AuditRecord(
            stream: stream,
            timestamp: timestamp,
            actor: stream == .daemon ? .daemon : .app,
            event: .streamOpened,
            detail: [
                "path": .string(activeFileURL.path),
                "schemaVersion": .int(auditSchemaVersion),
                "pid": .int(Int(ProcessInfo.processInfo.processIdentifier)),
                "uid": .int(Int(getuid())),
                "maxSegmentBytes": .int(policy.maxSegmentBytes),
                "maxRotatedSegments": .int(policy.maxRotatedSegments),
                "retentionDays": .int(policy.retentionDays),
                "chainRecovered": .bool(chainRecovered)
            ]
        ))
    }

    /// Appends `record`, assigning its sequence number and chaining it to the
    /// previous line. Failures are logged to `os.Logger` and swallowed.
    public func append(_ record: AuditRecord) {
        lock.lock()
        defer { lock.unlock() }
        appendLocked(record, allowRotation: true)
    }

    /// The real append. `allowRotation` is `false` for the rotation marker
    /// itself, which `rotate()` writes from inside this same critical
    /// section — `NSLock` is not recursive, and routing the marker back
    /// through `append` would deadlock the writer on its first rotation.
    private func appendLocked(_ record: AuditRecord, allowRotation: Bool) {
        var stamped = record
        stamped.stream = stream
        stamped.sequence = nextSequence
        var encoded = AuditLineEncoder.encode(stamped, previousHash: lastHash)
        var bytes = Data(encoded.line.utf8)

        if allowRotation, shouldRotate(incoming: bytes.count) {
            rotate()
            // Rotation appended its own marker, so this record's sequence and
            // parent hash both moved. Re-encode against the new head rather
            // than writing a line that claims a stale position.
            stamped.sequence = nextSequence
            encoded = AuditLineEncoder.encode(stamped, previousHash: lastHash)
            bytes = Data(encoded.line.utf8)
        }

        guard writeAll(bytes) else { return }
        bytesWritten += bytes.count
        lastHash = encoded.hash
        nextSequence += 1
    }

    // MARK: - Descriptor management

    private func openDescriptor() throws {
        let path = activeFileURL.path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, mode_t(filePermissions))
        guard fd >= 0 else {
            throw AuditLogWriterError.cannotOpen(path: path, errno: errno)
        }
        descriptor = fd
        var status = stat()
        bytesWritten = fstat(fd, &status) == 0 ? Int(status.st_size) : 0
    }

    /// Issues one `write(2)` and retries only on a short write or `EINTR`.
    /// Returns `false` once the write is hopeless so the caller can drop the
    /// record rather than spin.
    private func writeAll(_ data: Data) -> Bool {
        guard descriptor >= 0 else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let written = write(descriptor, base + offset, raw.count - offset)
                if written > 0 {
                    offset += written
                    continue
                }
                if written < 0, errno == EINTR {
                    continue
                }
                auditWriterLogger.error(
                    "audit append failed (errno \(errno, privacy: .public))"
                )
                return false
            }
            return true
        }
    }

    // MARK: - Rotation

    /// Whether appending `incoming` more bytes would push the active segment
    /// past its cap. An empty segment never rotates, so a single record
    /// larger than the cap still gets written rather than looping.
    private func shouldRotate(incoming: Int) -> Bool {
        bytesWritten > 0 && bytesWritten + incoming > policy.maxSegmentBytes
    }

    /// Shifts `.N` → `.N+1`, moves the active segment to `.1`, and reopens.
    /// The chain head is *not* reset: the first record in the new segment
    /// carries the last record of the old one as its `prev`, so the chain
    /// spans rotations and a deleted segment shows up as a break rather than
    /// as a clean restart.
    private func rotate() {
        let manager = FileManager.default
        if descriptor >= 0 {
            close(descriptor)
            descriptor = -1
        }

        let oldest = rotatedFileURL(index: policy.maxRotatedSegments)
        if policy.maxRotatedSegments == 0 {
            try? manager.removeItem(at: activeFileURL)
        } else {
            try? manager.removeItem(at: oldest)
            for index in stride(from: policy.maxRotatedSegments - 1, through: 1, by: -1) {
                let source = rotatedFileURL(index: index)
                guard manager.fileExists(atPath: source.path) else { continue }
                try? manager.moveItem(at: source, to: rotatedFileURL(index: index + 1))
            }
            try? manager.moveItem(at: activeFileURL, to: rotatedFileURL(index: 1))
        }

        pruneExpiredSegments(now: Date())
        bytesWritten = 0
        do {
            try openDescriptor()
        } catch {
            auditWriterLogger.error(
                "audit reopen after rotation failed: \(String(describing: error), privacy: .public)"
            )
            return
        }
        appendLocked(
            AuditRecord(
                stream: stream,
                timestamp: Date(),
                actor: stream == .daemon ? .daemon : .app,
                event: .rotated,
                detail: [
                    "rotatedTo": .string(rotatedFileURL(index: 1).lastPathComponent),
                    "maxSegmentBytes": .int(policy.maxSegmentBytes)
                ]
            ),
            allowRotation: false
        )
    }

    /// Deletes rotated segments last modified more than `retentionDays` ago.
    private func pruneExpiredSegments(now: Date) {
        guard policy.retentionDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(policy.retentionDays) * 86400)
        let manager = FileManager.default
        for index in 1 ... max(1, policy.maxRotatedSegments) {
            let url = rotatedFileURL(index: index)
            guard
                let attributes = try? manager.attributesOfItem(atPath: url.path),
                let modified = attributes[.modificationDate] as? Date,
                modified < cutoff
            else { continue }
            try? manager.removeItem(at: url)
        }
    }

    // MARK: - Chain recovery

    /// Restores `lastHash` and `nextSequence` from the last complete line of
    /// the active segment, falling back to the most recent rotated segment
    /// when the active one is empty (the state right after a rotation that
    /// crashed before its first append).
    private func recoverChainHead() {
        let candidates = [activeFileURL] + (0 ..< policy.maxRotatedSegments).map {
            rotatedFileURL(index: $0 + 1)
        }
        for url in candidates {
            guard let line = Self.lastLine(of: url) else { continue }
            guard let hash = AuditLineEncoder.hash(inLine: line) else { continue }
            lastHash = hash
            nextSequence = (Self.sequence(inLine: line) ?? 0) + 1
            chainRecovered = true
            return
        }
    }

    /// Reads the final non-empty line of `url`. Reads the whole file: audit
    /// segments are capped at a few megabytes and this runs once per process.
    private static func lastLine(of url: URL) -> String? {
        guard
            let data = try? BoundedRegularFileReader.read(url, maximumBytes: 16_777_216),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map(String.init)
    }

    /// Pulls `seq` out of a written line with a narrow scan rather than a
    /// full JSON parse, so a partially-written trailing line cannot make
    /// recovery throw.
    private static func sequence(inLine line: String) -> Int? {
        guard let range = line.range(of: "\"seq\":") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Failure modes for opening an audit stream.
public enum AuditLogWriterError: Error, Equatable {
    /// The segment file could not be opened for appending. `errno` is the
    /// raw POSIX code — `EACCES` is the expected one when a non-root process
    /// tries to open the daemon stream.
    case cannotOpen(path: String, errno: Int32)
}
