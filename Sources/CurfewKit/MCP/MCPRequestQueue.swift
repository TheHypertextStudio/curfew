import Foundation

/// Synchronised read/write access to the MCP request queue JSON file at
/// ``SharedPaths/mcpRequestQueue``.
///
/// `curfew-mcp` uses this to append new requests and poll for resolution.
/// The Curfew app's `MCPRequestMonitor` uses it to load pending entries
/// and write approval decisions.
///
/// Concurrency model: the file is small (tens of entries at most) and
/// access is infrequent, so a simple file-lock-free read-modify-write
/// is used. The MCP server serialises its own calls (one client request
/// at a time over stdio); the app serialises via `@MainActor`. Worst case:
/// simultaneous app approval + new MCP append clobbers one entry — benign
/// because the app re-reads before every consent sheet.
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
    /// its parent directory if absent.
    ///
    /// Throws on filesystem errors — the caller is `curfew-mcp` which maps
    /// the error to a JSON-RPC error response.
    public static func append(_ request: MCPPendingRequest) throws {
        var requests = load()
        requests.append(request)
        try save(requests)
    }

    /// Replaces the entry matching `request.id` with the updated value and
    /// persists. Used by the Curfew app to write the approval decision.
    ///
    /// No-ops silently when the request ID is not in the queue (app may have
    /// already pruned completed entries since the last read).
    public static func update(_ request: MCPPendingRequest) throws {
        var requests = load()
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else {
            return
        }
        requests[index] = request
        try save(requests)
    }

    /// Removes all resolved (approved/denied) requests older than `cutoff`.
    /// Call periodically from the app to prevent the queue file from growing
    /// unbounded.
    public static func pruneResolved(olderThan cutoff: Date) throws {
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

    // MARK: - Private helpers

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
