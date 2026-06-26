import Foundation

// Entry point for the `curfew-mcp` MCP server.
//
// Default behaviour: stdio JSON-RPC on stdin/stdout. Claude Desktop and
// other MCP hosts spawn this binary and pipe stdin/stdout.
//
// ```json
// {
//   "mcpServers": {
//     "curfew": {
//       "command": "/path/to/curfew-mcp",
//       "args": []
//     }
//   }
// }
// ```
//
// Optional secondary transport: pass `--http` (and optionally `--port
// <n>`) to also bind a loopback-only HTTP listener that exposes the
// same tool registry. Useful for multi-process setups and remote MCP
// clients over SSH. The HTTP transport is started alongside the stdio
// loop — the main thread runs stdio; the listener runs on the main
// run loop via `NWListener(queue:.main)`.

/// Raw process arguments — parsed manually because the MCP host
/// launches this binary with positional args only; ArgumentParser's
/// overhead isn't justified for two flags.
let arguments = CommandLine.arguments
/// `--http` opt-in flag. Runs an additional loopback HTTP listener.
let httpEnabled = arguments.contains("--http")
/// Port for the HTTP listener when enabled. Defaults to 9847.
let port: UInt16 = {
    if let flagIndex = arguments.firstIndex(of: "--port"),
       flagIndex + 1 < arguments.count,
       let parsed = UInt16(arguments[flagIndex + 1]) {
        return parsed
    }
    return 9847
}()

/// The single MCP server instance. Both transports share it.
let server = MCPServer()

if httpEnabled {
    let http = StreamableHTTPTransport(server: server, port: port)
    http.start()
}

server.run()
