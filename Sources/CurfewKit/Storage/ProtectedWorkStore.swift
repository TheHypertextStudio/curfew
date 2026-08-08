import Foundation
import OSLog

private let protectedWorkLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "protected-work"
)

/// Who filed a claim. Recorded so the lockout screen and the retrospective can
/// say *what* held enforcement off, and so a user who never wanted agents to
/// file claims can tell at a glance that one did.
public enum ProtectedWorkSource: String, Codable, Equatable, Sendable {
    /// The Curfew app itself.
    case app
    /// `curfew-ctl work claim`, typically from a shell script that wraps a
    /// long-running job.
    case cli
    /// The `curfew_declare_work` MCP tool.
    case mcp
}

/// One lease asserting that delegated work is in flight.
///
/// A claim is a heartbeat, not a reservation. It expires on its own and the
/// holder must re-assert to keep it alive, so an agent that crashes, is killed,
/// or simply finishes stops protecting anything within one lease. Nothing has
/// to notice the death and clean up.
public struct ProtectedWorkClaim: Codable, Equatable, Identifiable, Sendable {
    /// Stable key. Callers that renew pass the same id; callers that don't
    /// get a fresh one and their old claim simply expires.
    public let id: UUID

    /// Human-readable description of the work, e.g. `"delegate: build athena"`.
    public var label: String

    /// Which surface filed it.
    public var source: ProtectedWorkSource

    /// When the claim was first filed. Preserved across renewals so the
    /// activity log can show how long a job actually ran.
    public var startedAt: Date

    /// When the claim stops counting. Renewal moves this forward.
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        source: ProtectedWorkSource,
        startedAt: Date,
        expiresAt: Date
    ) {
        self.id = id
        self.label = label
        self.source = source
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    /// Whether the claim still counts at `now`.
    public func isActive(at now: Date) -> Bool {
        now < expiresAt
    }
}

/// Atomic JSON store for ``ProtectedWorkClaim`` leases at
/// ``SharedPaths/protectedWorkClaims``.
///
/// Follows the same shape as ``LockoutDeadlineStore``: a small file, atomic
/// writes, and every read failure treated as "no record". The failure
/// direction is the opposite of the deadline store's, though, and
/// deliberately so — an unreadable claims file means *no protection*, so a
/// corrupt or missing file can never be used to hold enforcement off.
public struct ProtectedWorkStore {
    private let fileManager: FileManager

    /// Where the claims live. Exposed for tests; production resolves it from
    /// ``SharedPaths``.
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
        recordURL: URL = SharedPaths.protectedWorkClaims
    ) {
        self.fileManager = fileManager
        self.recordURL = recordURL
    }

    // MARK: - Reads

    /// Every claim on disk, expired ones included.
    public func load() -> [ProtectedWorkClaim] {
        guard fileManager.fileExists(atPath: recordURL.path),
              let data = try? Data(contentsOf: recordURL),
              let claims = try? decoder.decode([ProtectedWorkClaim].self, from: data)
        else {
            return []
        }
        return claims
    }

    /// Claims that have not expired at `now`.
    public func activeClaims(now: Date) -> [ProtectedWorkClaim] {
        load().filter { $0.isActive(at: now) }
    }

    /// Whether anything is holding enforcement off at `now`.
    public func hasActiveWork(now: Date) -> Bool {
        !activeClaims(now: now).isEmpty
    }

    // MARK: - Writes

    /// Files a new claim or renews an existing one, and drops every expired
    /// claim in the same write so the file cannot grow without bound.
    ///
    /// - Parameters:
    ///   - id: pass an existing claim's id to renew it; omit to file a new one.
    ///   - label: human-readable description of the work.
    ///   - source: which surface is filing.
    ///   - leaseMinutes: requested lease, clamped by `policy`.
    ///   - now: current clock time.
    ///   - policy: supplies the lease clamp.
    /// - Returns: the stored claim, with its granted (possibly clamped) expiry.
    @discardableResult
    public func claim(
        id: UUID? = nil,
        label: String,
        source: ProtectedWorkSource,
        leaseMinutes: Int? = nil,
        now: Date,
        policy: ProtectedWorkPolicy
    ) throws -> ProtectedWorkClaim {
        let granted = policy.leaseMinutes(requested: leaseMinutes)
        let expiry = now.addingTimeInterval(TimeInterval(granted * 60))

        var claims = load().filter { $0.isActive(at: now) }
        var stored: ProtectedWorkClaim

        if let id, let index = claims.firstIndex(where: { $0.id == id }) {
            claims[index].label = label
            claims[index].source = source
            claims[index].expiresAt = expiry
            stored = claims[index]
        } else {
            stored = ProtectedWorkClaim(
                id: id ?? UUID(),
                label: label,
                source: source,
                startedAt: now,
                expiresAt: expiry
            )
            claims.append(stored)
        }

        try save(claims)
        protectedWorkLogger.info(
            "protected-work claim \(stored.id.uuidString, privacy: .public) held for \(granted, privacy: .public) min"
        )
        return stored
    }

    /// Drops one claim. No-ops when the id is unknown.
    public func release(id: UUID) throws {
        let remaining = load().filter { $0.id != id }
        try save(remaining)
        protectedWorkLogger.info("protected-work claim \(id.uuidString, privacy: .public) released")
    }

    /// Drops every claim. Called when a lockout window ends so the next one
    /// starts from nothing.
    public func clear() throws {
        guard fileManager.fileExists(atPath: recordURL.path) else { return }
        try fileManager.removeItem(at: recordURL)
    }

    // MARK: - Private

    private func save(_ claims: [ProtectedWorkClaim]) throws {
        try fileManager.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(claims).write(to: recordURL, options: .atomic)
        // Claim labels quote whatever the agent was doing; on a shared machine
        // that should not be world-readable. `Data.write` lands at 0644, so
        // tighten after the atomic rename completes.
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: recordURL.path
        )
    }
}

/// The two files the enforcement paths read to decide whether destroying the
/// user's background work is safe right now.
///
/// Bundled so the app can hold one injectable value instead of two, which is
/// what lets a wiring test point the whole carve-out at a temporary directory
/// and assert that settings, live claims, and the emergency release actually
/// reach the shutdown workflow.
public struct ProtectedWorkStores {
    /// Live protected-work leases.
    public var claims: ProtectedWorkStore

    /// The emergency release record.
    public var breakGlass: BreakGlassStore

    public init(
        claims: ProtectedWorkStore = ProtectedWorkStore(),
        breakGlass: BreakGlassStore = BreakGlassStore()
    ) {
        self.claims = claims
        self.breakGlass = breakGlass
    }
}
