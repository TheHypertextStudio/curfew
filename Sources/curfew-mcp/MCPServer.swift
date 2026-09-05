import CurfewKit
import Foundation

/// JSON-RPC 2.0 server implementing the Model Context Protocol over stdio.
///
/// Transport: newline-delimited JSON on stdin/stdout. Each JSON object is
/// one complete message; `stderr` is reserved for diagnostics only and is
/// never part of the protocol stream. Claude Desktop (and any other MCP
/// host) spawns `curfew-mcp` as a subprocess and pipes stdin/stdout.
///
/// The server is single-threaded: it reads one request at a time, handles
/// it synchronously, and writes the response before reading the next.
/// MCP's stdio transport guarantees requests arrive serially, so no
/// concurrency management is needed.
///
/// Protocol version: 2026-07-28.
final class MCPServer {
    /// All tools exposed to MCP clients, each with its JSON Schema for
    /// input validation and a handler that produces the response content.
    private let tools: [MCPTool]

    /// Re-usable formatters; created once rather than per-call.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a server with the full tool set. `MCPTool.all` is resolved
    /// eagerly so schema validation errors surface at process start,
    /// not mid-session on first `tools/list`.
    init() {
        self.tools = MCPTool.all
        encoder.outputFormatting = [.sortedKeys]
    }

    /// Runs the read–handle–write loop until stdin closes. This call never
    /// returns normally; the process exits when the MCP host closes its end
    /// of the pipe.
    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else {
                continue
            }
            let response = handle(line: line)
            if let response {
                writeLine(response)
            }
        }
    }

    // MARK: - Request dispatch

    /// Parses one JSON-RPC frame and returns the response frame string,
    /// or `nil` when the incoming message was a notification that takes
    /// no response. Invalid JSON returns `-32700` (Parse error).
    func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return errorResponse(rawID: nil, code: -32700, message: "Parse error")
        }

        // JSON-RPC 2.0 IDs may be Int, String, or null. Preserve the original
        // value — the host matches responses to requests by exact ID equality.
        let rawID = obj["id"]
        let method = obj["method"] as? String ?? ""
        let params = obj["params"] as? [String: Any]

        // Notifications have no "id" field and require no response.
        if rawID == nil || rawID is NSNull {
            handleNotification(method: method, params: params)
            return nil
        }

        switch method {
        case "initialize":
            return handleInitialize(rawID: rawID, params: params)
        case "ping":
            return successResponse(rawID: rawID, result: [:])
        case "tools/list":
            return handleToolsList(rawID: rawID)
        case "tools/call":
            return handleToolsCall(rawID: rawID, params: params)
        default:
            return errorResponse(rawID: rawID, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Method handlers

    private func handleInitialize(rawID: Any?, params: [String: Any]?) -> String {
        let result: [String: Any] = [
            "protocolVersion": "2026-07-28",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": "curfew-mcp",
                "version": "0.0.1"
            ]
        ]
        return successResponse(rawID: rawID, result: result)
    }

    /// Builds the `tools/list` response — a flat array of `{name, description,
    /// inputSchema}` entries. MCP hosts display these in their tool picker.
    private func handleToolsList(rawID: Any?) -> String {
        let toolDefs = tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.inputSchema
            ]
        }
        return successResponse(rawID: rawID, result: ["tools": toolDefs])
    }

    /// Dispatches a `tools/call` to the matching `MCPTool`. Invalid names
    /// return JSON-RPC `-32602` (invalid params); tool-side failures return
    /// `-32603` (internal error) with the error's localised description.
    private func handleToolsCall(rawID: Any?, params: [String: Any]?) -> String {
        guard let name = params?["name"] as? String else {
            return errorResponse(rawID: rawID, code: -32602, message: "Missing tool name")
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return errorResponse(rawID: rawID, code: -32602, message: "Unknown tool: \(name)")
        }

        let args = params?["arguments"] as? [String: Any] ?? [:]
        do {
            let content = try tool.call(args)
            return successResponse(rawID: rawID, result: ["content": content])
        } catch {
            return errorResponse(
                rawID: rawID,
                code: -32603,
                message: "Tool error: \(error.localizedDescription)"
            )
        }
    }

    /// Handles JSON-RPC notifications (no `id` field, no response expected).
    /// We don't act on any notification today — just log to stderr for
    /// post-hoc debugging when users share transcripts.
    private func handleNotification(method: String, params: [String: Any]?) {
        // Notifications that require no response (e.g. notifications/initialized).
        // Log to stderr for diagnostics; never write to stdout.
        fputs("[curfew-mcp] notification: \(method)\n", stderr)
    }

    // MARK: - Response builders

    private func successResponse(rawID: Any?, result: [String: Any]) -> String {
        serialize(["jsonrpc": "2.0", "id": rawID ?? NSNull(), "result": result])
    }

    /// Builds a JSON-RPC 2.0 error response using the supplied `code` and
    /// `message`. `rawID` is preserved verbatim so the host can match the
    /// error back to the originating request.
    private func errorResponse(rawID: Any?, code: Int, message: String) -> String {
        serialize([
            "jsonrpc": "2.0",
            "id": rawID ?? NSNull(),
            "error": ["code": code, "message": message] as [String: Any]
        ])
    }

    /// Serialises a response object to a single-line JSON string. Falls
    /// back to a hard-coded internal-error envelope if encoding fails so
    /// the caller always has *something* to send back — a dropped
    /// response on the wire would hang the client.
    private func serialize(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Serialisation failed\"}}"
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes one JSON-RPC frame to stdout followed by a newline. Flushes
    /// explicitly because some hosts launch the subprocess with buffered
    /// stdio and would otherwise wait forever for a response that never
    /// made it past the C buffer.
    private func writeLine(_ line: String) {
        print(line)
        // Flush immediately — stdio is line-buffered in most contexts, but
        // forcing a flush ensures the MCP host receives the response without
        // waiting for the buffer to fill.
        fflush(stdout)
    }
}
