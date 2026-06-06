import Foundation
import OSLog

private let socketLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "mcp-socket-server"
)

/// In-app Unix domain socket listener that receives MCP write requests
/// from `curfew-mcp` / `curfew-ctl` directly, bypassing the JSON queue
/// file + `DispatchSourceFileSystemObject` latency.
///
/// v0.2 ships an inert seam: `start()` creates the socket directory but
/// does not yet bind a listener. `MCPSocketClient` detects the absent
/// socket and falls through to `MCPRequestQueue.append`, which is the
/// v0.1 delivery mechanism and already works. A future revision plugs
/// in a POSIX `socket`/`bind`/`accept` loop here so the fast path
/// becomes observable.
///
/// Rationale for the staged approach: `NWListener` with `AF_UNIX` has
/// limited support on macOS and interacts awkwardly with the main
/// actor — a half-implemented listener that races the queue path would
/// be worse than no listener at all. The client-side fallback keeps the
/// end-to-end behaviour stable until the full listener lands.
///
/// Started/stopped alongside `MCPRequestMonitor` in the app model.
@MainActor
final class MCPSocketServer {
    /// `~/Library/Application Support/Curfew/mcp.sock` — matches
    /// `MCPSocketClient.socketURL` so the two sides agree on the
    /// rendezvous point once the listener lands.
    nonisolated static var defaultPath: String {
        SharedPaths.applicationSupport.appendingPathComponent("mcp.sock").path
    }

    /// Default-constructed — all configuration is derived from
    /// `SharedPaths`. `nonisolated` so the app model can default-initialise
    /// one inside its synchronous init without hopping actors.
    nonisolated init() {}

    /// Ensures the socket directory exists. The socket file itself is
    /// not created yet; `MCPSocketClient` interprets its absence as
    /// "fall through to the queue path."
    func start() {
        // Skip the directory creation in the unit-test host so gating tests
        // that flip the MCP flag on do not write into the Application Support
        // container during `xcodebuild test`.
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        try? FileManager.default.createDirectory(
            at: SharedPaths.applicationSupport,
            withIntermediateDirectories: true
        )
        socketLogger.debug("MCP socket seam active (listener not yet bound)")
    }

    /// Removes any stale socket file a future listener left behind so a
    /// restart starts clean.
    func stop() {
        guard !RuntimeEnvironment.isUnitTestHost else { return }
        try? FileManager.default.removeItem(atPath: Self.defaultPath)
    }
}
