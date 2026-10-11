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

    /// Atomically appends `request` to the queue file, creating the file and
    /// its parent directory if absent. Holds the cross-process lock for the
    /// full load-mutate-save cycle so a concurrent `update`/`append` from the
    /// other process can't overwrite this append.
    ///
    /// Throws on filesystem errors — the caller is `curfew-mcp` which maps
    /// the error to a JSON-RPC error response.
    public static func append(_ request: MCPPendingRequest) throws {
        try withExclusiveLock {
            var requests = load()
            requests.append(request)
            try save(requests)
        }
    }

    /// Replaces the entry matching `request.id` with the updated value and
    /// persists. Used by the Curfew app to write the approval decision.
    ///
    /// No-ops silently when the request ID is not in the queue (app may have
    /// already pruned completed entries since the last read).
    public static func update(_ request: MCPPendingRequest) throws {
        try withExclusiveLock {
            var requests = load()
            guard let index = requests.firstIndex(where: { $0.id == request.id }) else {
                return
            }
            requests[index] = request
            try save(requests)
        }
    }

    /// Removes all resolved (approved/denied) requests older than `cutoff`.
    /// Call periodically from the app to prevent the queue file from growing
    /// unbounded.
    public static func pruneResolved(olderThan cutoff: Date) throws {
        try withExclusiveLock {
            let requests = load().filter { request in
                if request.status == .pending {
                    return true
                }
                guard let resolvedAt = request.resolvedAt else {
                    return false
                }
                return resolvedAt > cutoff
            }
            try save(requests)
        }
    }

    // MARK: - Private helpers

    /// Runs `body` while holding an exclusive advisory lock on a `.lock`
    /// sidecar file next to the queue, serialising every read-modify-write
    /// across the app process and `curfew-mcp` subprocesses. Falls back to
    /// running unlocked if the lock file itself can't be opened, so a
    /// filesystem hiccup degrades to the old (racy) behaviour rather than
    /// hard-failing every queue write.
    private static func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        let lockURL = SharedPaths.mcpRequestQueue.appendingPathExtension("lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            return try body()
        }
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func save(_ requests: [MCPPendingRequest]) throws {
        let url = SharedPaths.mcpRequestQueue
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(requests)
        try data.write(to: url, options: .atomic)
        // Queue entries carry free-form override justifications; on a shared
        // machine these should not be world-readable. An atomic write via
        // `NSData.write` lands at default `0644` on macOS — explicitly
        // tighten to `0600` after the rename completes.
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
