import Foundation

/// Client used by the MCP server binary to hand off pending write requests
/// to the running app. Prefers a Unix domain socket at
/// `~/Library/Application Support/Curfew/mcp.sock` — direct delivery with
/// no filesystem watcher latency — and falls back to appending the request
/// to `MCPRequestQueue` when the socket is unavailable (app not running,
/// permission denied, any connection error).
///
/// The fallback path is the original v0.1 delivery mechanism; the socket
/// path is a latency-reduction optimisation, never the sole channel. If
/// the socket disappears mid-session the client keeps working.
///
/// Kept deliberately minimal in v0.2: each `send` is a single connect /
/// write / close. A multiplexed long-lived connection is a later tuning.
public enum MCPSocketClient {
    /// Canonical socket path. Matches `MCPSocketServer.socketURL`.
    public static var socketURL: URL {
        SharedPaths.applicationSupport.appendingPathComponent("mcp.sock")
    }

    /// Enqueues `request` via the fastest available channel. Returns `true`
    /// when the socket delivery succeeded; `false` indicates the queue
    /// fallback was used (also a success for the caller — the request is
    /// queued either way).
    @discardableResult
    public static func send(_ request: MCPPendingRequest) throws -> Bool {
        if trySocketDelivery(request) {
            return true
        }
        try MCPRequestQueue.append(request)
        return false
    }

    /// Attempts to deliver `request` via the Unix domain socket. Returns
    /// `false` on any error — connection refused, file missing, write
    /// short, timeout — so the caller can fall through to the queue.
    private static func trySocketDelivery(_ request: MCPPendingRequest) -> Bool {
        let path = socketURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { pathPointer in
            path.withCString { source in
                _ = strlcpy(
                    pathPointer.withMemoryRebound(
                        to: CChar.self,
                        capacity: MemoryLayout.size(ofValue: addr.sun_path)
                    ) { $0 },
                    source,
                    MemoryLayout.size(ofValue: addr.sun_path)
                )
            }
        }

        let result = withUnsafePointer(to: &addr) { addrPointer in
            addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { return false }

        guard
            let data = try? JSONEncoder.iso8601.encode(request),
            let newline = "\n".data(using: .utf8)
        else { return false }
        let payload = data + newline

        let written = payload.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return write(fd, base, buffer.count)
        }
        return written == payload.count
    }
}

private extension JSONEncoder {
    /// Shared encoder whose date strategy matches
    /// `MCPRequestQueue.encoder` so socket and queue entries round-trip
    /// through the same decoder on the app side.
    static let iso8601: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
