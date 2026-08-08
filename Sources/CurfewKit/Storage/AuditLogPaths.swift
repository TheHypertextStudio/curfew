import Foundation

/// Where the audit streams live on disk, and how much of them Curfew keeps.
///
/// Deliberately separate from ``SharedPaths``. Everything in `SharedPaths` is
/// *state* the three processes must agree on, and a disagreement there is a
/// correctness bug. The audit log is a write-only side channel: nothing reads
/// it to make a decision, so it does not belong in the rendezvous file. It
/// also follows a different macOS convention — `Library/Logs`, which Console
/// and `sysdiagnose` already know about — rather than Application Support.
public enum AuditLogPaths {
    /// `~/Library/Logs/Curfew/` (or `Curfew (Dev)` on a development build,
    /// mirroring the flavor split ``SharedPaths`` applies so a dev run never
    /// interleaves with the production install's audit history).
    public static var userDirectory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(
                "Curfew\(CurfewFlavor.current.displaySuffix)",
                isDirectory: true
            )
    }

    /// `/Library/Logs/Curfew/` — root-owned, written only by `curfew-daemon`.
    ///
    /// Not flavor-suffixed: there is one privileged daemon per machine, and a
    /// dev build does not install one. Root ownership is the point — the user
    /// cannot rewrite the daemon's history of what it did to their machine
    /// without escalating first, which makes this the one stream whose hash
    /// chain resists the person being audited.
    public static var privilegedDirectory: URL {
        URL(fileURLWithPath: "/Library/Logs/Curfew", isDirectory: true)
    }

    /// Directory for `stream`.
    public static func directory(for stream: AuditStream) -> URL {
        switch stream {
        case .app: userDirectory
        case .daemon: privilegedDirectory
        }
    }

    /// File-name stem for `stream`. The active segment is `<stem>.jsonl` and
    /// rotated segments are `<stem>.1.jsonl` … `<stem>.N.jsonl`.
    public static func baseName(for stream: AuditStream) -> String {
        switch stream {
        case .app: "curfew-app"
        case .daemon: "curfew-daemon"
        }
    }

    /// Full path to the active segment for `stream`.
    public static func activeFile(for stream: AuditStream) -> URL {
        directory(for: stream)
            .appendingPathComponent(baseName(for: stream) + ".jsonl")
    }
}

/// Rotation and retention policy for one audit stream.
///
/// The defaults cap a stream at 25 MiB. At the volume Curfew actually writes
/// — a few hundred records on a heavy day, roughly 300 bytes each — a 5 MiB
/// segment holds well over a year, so the size cap is a disk-safety backstop
/// and `retentionDays` is what normally decides how far back history goes.
public struct AuditRotationPolicy: Equatable, Sendable {
    /// Rotate once appending the next line would push the active segment past
    /// this many bytes. Default 5 MiB.
    public var maxSegmentBytes: Int

    /// How many rotated segments to keep behind the active one. Default 4,
    /// giving five files and a 25 MiB ceiling per stream.
    public var maxRotatedSegments: Int

    /// Delete a rotated segment once it has gone this long without being
    /// written. Default 90 days. Checked at rotation time only — Curfew never
    /// runs a background sweeper for this.
    public var retentionDays: Int

    /// Creates a policy. Callers that want the shipping behaviour should use
    /// ``standard``; the memberwise initialiser exists for tests, which shrink
    /// `maxSegmentBytes` to a few hundred bytes to exercise rotation.
    public init(maxSegmentBytes: Int, maxRotatedSegments: Int, retentionDays: Int) {
        self.maxSegmentBytes = max(1, maxSegmentBytes)
        self.maxRotatedSegments = max(0, maxRotatedSegments)
        self.retentionDays = max(0, retentionDays)
    }

    /// The shipping defaults: 5 MiB segments, 4 rotated segments, 90 days.
    public static let standard = AuditRotationPolicy(
        maxSegmentBytes: 5 * 1024 * 1024,
        maxRotatedSegments: 4,
        retentionDays: 90
    )
}
