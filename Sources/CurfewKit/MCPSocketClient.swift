import Foundation

/// Client used by the MCP server binary to hand off pending write requests
/// to the running app. v0.2 ships an inert seam: `send` always falls
/// through to `MCPRequestQueue.append`, which is the v0.1 delivery
/// mechanism and already works.
///
/// The type exists so the MCP tool callsites already use the faster
/// "socket first, queue fallback" shape. A future revision adds the
/// POSIX `socket`/`connect`/`write` loop here without touching any
/// callers. The server-side counterpart is `MCPSocketServer` (app target).
///
/// Why an inert seam instead of the real listener today: the hand-rolled
/// AF_UNIX path runs into Swift's exclusive-access diagnostics when
/// writing into `sockaddr_un.sun_path`, and a half-wired listener that
/// races the queue would be worse than no listener at all. Keeping the
/// seam means the API doesn't change when the listener lands.
public enum MCPSocketClient {
    /// Canonical socket path. Paired with `MCPSocketServer.defaultPath`.
    public static var socketURL: URL {
        SharedPaths.applicationSupport.appendingPathComponent("mcp.sock")
    }

    /// Enqueues `request` via the fastest available channel. Today the
    /// socket path is a no-op; the queue fallback handles delivery. The
    /// return value describes which channel was used — `false` is the
    /// expected steady state until the POSIX listener lands.
    @discardableResult
    public static func send(_ request: MCPPendingRequest) throws -> Bool {
        try MCPRequestQueue.append(request)
        return false
    }
}
