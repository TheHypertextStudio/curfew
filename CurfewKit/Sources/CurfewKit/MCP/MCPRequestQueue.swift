import Darwin
import Foundation

/// Synchronised read/write access to the MCP request queue JSON file at
/// ``SharedPaths/mcpRequestQueue``.
///
/// `curfew-mcp` uses this to append new requests and poll for resolution.
/// The Curfew app's `MCPRequestMonitor` uses it to load pending entries
/// and write approval decisions.
///
/// Concurrency model: `curfew-mcp` (a separate process) and the app both
/// read-modify-write the *entire file* — `load()` the current array, mutate
/// it, `save()` the whole thing back. Two processes doing that concurrently
/// isn't "worst case: one entry's status gets clobbered" — it's real data
/// loss: whichever save() runs second overwrites the first's change
/// entirely, so an append racing an approval can make the just-appended
/// request vanish, not just show it as unresolved. `append`/`update`/
/// `pruneResolved` hold an exclusive `flock()` on a sidecar lock file for
/// their full read-modify-write cycle to close that window. `load()` alone
/// stays unlocked — Foundation's `.atomic` write option already makes a
/// concurrent plain read see either the old or the new file in full, never
/// a torn one.
public enum MCPRequestQueue {
    private static let maximumBytes = 16 * 1024 * 1024
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Reads all requests from the queue file. Returns an empty array when
    /// the file doesn't exist (app not yet launched) or is unreadable.
    public static func load() -> [MCPPendingRequest] {
        let url = SharedPaths.mcpRequestQueue
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return (try? decoder.decode([MCPPendingRequest].self, from: data)) ?? []
    }

    /// Strict reads distinguish an absent queue from damaged or inaccessible state.
    public static func loadChecked(from url: URL = SharedPaths
        .mcpRequestQueue) throws -> [MCPPendingRequest] {
        guard let data = try BoundedRegularFileReader.read(url, maximumBytes: maximumBytes)
        else { return [] }
        return try decoder.decode([MCPPendingRequest].self, from: data)
    }

    /// Atomically appends `request` to the queue file, creating the file and
    /// its parent directory if absent. Holds the cross-process lock for the
    /// full load-mutate-save cycle so a concurrent `update`/`append` from the
    /// other process can't overwrite this append.
    ///
    /// Throws on filesystem errors — the caller is `curfew-mcp` which maps
    /// the error to a JSON-RPC error response.
    public static func append(
        _ request: MCPPendingRequest,
        to url: URL = SharedPaths.mcpRequestQueue
    ) throws {
        try withExclusiveLock(at: url) {
            var requests = try loadChecked(from: url)
            if let existing = requests.first(where: { $0.id == request.id }) {
                guard existing.tool == request.tool,
                      existing.argumentsJSON == request.argumentsJSON else {
                    throw MCPRequestQueueError.conflictingIdentity
                }
                return
            }
            requests.append(request)
            try save(requests, to: url)
        }
    }

    /// Replaces the entry matching `request.id` with the updated value and
    /// persists. Used by the Curfew app to write the approval decision.
    ///
    /// No-ops silently when the request ID is not in the queue (app may have
    /// already pruned completed entries since the last read).
    @discardableResult
    public static func update(
        _ request: MCPPendingRequest, to url: URL = SharedPaths.mcpRequestQueue
    ) throws -> Bool {
        try withExclusiveLock(at: url) {
            var requests = try loadChecked(from: url)
            guard let index = requests.firstIndex(where: { $0.id == request.id }) else {
                return false
            }
            guard requests[index].tool == request.tool,
                  requests[index].argumentsJSON == request.argumentsJSON else {
                throw MCPRequestQueueError.conflictingIdentity
            }
            requests[index] = request
            try save(requests, to: url)
            return true
        }
    }

    public struct PrunePlan {
        public let queueURL: URL
        public let queuedCount: Int
        public let pendingCount: Int
        public let protectedResolvedCount: Int
        fileprivate let candidates: [MCPPendingRequest]

        public var candidateIDs: [UUID] {
            candidates.map(\.id)
        }
    }

    public struct PruneResult {
        public let removedIDs: [UUID]
        public let retainedCount: Int
    }

    public static func previewResolvedPrune(
        before cutoff: Date?, from url: URL = SharedPaths.mcpRequestQueue,
        protectedRequestIDs: () throws -> Set<UUID> = { try protectedGrantRequestIDs() }
    ) throws -> PrunePlan {
        let requests = try loadChecked(from: url)
        let protected = try protectedRequestIDs()
        let resolved = requests.filter { $0.status != .pending }
        let unprotected = resolved.filter { !protected.contains($0.id) }
        let candidates = unprotected.filter { request in
            guard let cutoff else { return true }
            return request.resolvedAt.map { $0 < cutoff } ?? false
        }
        return PrunePlan(
            queueURL: url, queuedCount: requests.count,
            pendingCount: requests.count - resolved.count,
            protectedResolvedCount: resolved.count - unprotected.count,
            candidates: candidates
        )
    }

    public static func pruneResolved(
        _ plan: PrunePlan,
        protectedRequestIDs: () throws -> Set<UUID> = { try protectedGrantRequestIDs() }
    ) throws -> PruneResult {
        let reviewed = Dictionary(grouping: plan.candidates, by: \.id)
        return try withExclusiveLock(at: plan.queueURL) {
            let requests = try loadChecked(from: plan.queueURL)
            let protected = try protectedRequestIDs()
            var removed = [UUID]()
            let retained = requests.filter { request in
                guard !protected.contains(request.id),
                      reviewed[request.id]?.contains(request) == true else { return true }
                removed.append(request.id)
                return false
            }
            if !removed.isEmpty {
                try save(retained, to: plan.queueURL)
            }
            return PruneResult(removedIDs: removed, retainedCount: retained.count)
        }
    }

    public static func protectedGrantRequestIDs(
        from store: EnforcementRuntimeStateStore = .production()
    ) throws -> Set<UUID> {
        guard let state = try store.load() else {
            throw CocoaError(.fileNoSuchFile)
        }
        return Set((state.mcpGrantReceipts ?? []).map(\.requestID))
            .union(state.legacyMCPGrantRequestIDs ?? [])
    }

    /// Removes completed requests before the cutoff while retaining grant recovery records.
    public static func pruneResolved(olderThan cutoff: Date) throws {
        let plan = try previewResolvedPrune(before: cutoff)
        _ = try pruneResolved(plan)
    }

    // MARK: - Private helpers

    /// Runs `body` while holding an exclusive advisory lock on a `.lock`
    /// sidecar file next to the queue, serialising every read-modify-write
    /// across the app process and `curfew-mcp` subprocesses. Lock failures
    /// must stop the write because an unlocked retry can discard another request.
    private static func withExclusiveLock<T>(
        at url: URL = SharedPaths.mcpRequestQueue,
        _ body: () throws -> T
    ) throws -> T {
        let lockURL = url.appendingPathExtension("lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else {
            throw BoundedRegularFileReadError.unsafeEntry
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func save(
        _ requests: [MCPPendingRequest],
        to url: URL = SharedPaths.mcpRequestQueue
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(requests)
        guard data.count <= maximumBytes else {
            throw MCPRequestQueueError.full
        }
        // Acknowledgement must reach disk before the app clears its grant receipt.
        try BreakGlassPrivateFileWriter.write(data, to: url, replaceExisting: true)
    }
}
