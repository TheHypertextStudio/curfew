import Foundation

/// Entry point for the `curfew-mcp` MCP server.
///
/// Run this binary as an MCP stdio server. Claude Desktop and other MCP
/// hosts that support stdio transport can spawn it via a config entry like:
///
/// ```json
/// {
///   "mcpServers": {
///     "curfew": {
///       "command": "/path/to/curfew-mcp",
///       "args": []
///     }
///   }
/// }
/// ```
///
/// The server never writes to stderr except for diagnostics; all protocol
/// traffic uses stdout. The process runs until stdin is closed (host
/// disconnects).
MCPServer().run()
