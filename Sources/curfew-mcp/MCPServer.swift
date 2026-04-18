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
/// Protocol version: 2024-11-05 (initial stable MCP release).
final class MCPServer {
    /// All tools exposed to MCP clients, each with its JSON Schema for
    /// input validation and a handler that produces the response content.
    private let tools: [MCPTool]

    /// Re-usable formatters; created once rather than per-call.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": "curfew-mcp",
                "version": "0.1.0"
            ]
        ]
        return successResponse(rawID: rawID, result: result)
    }

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

    private func handleNotification(method: String, params: [String: Any]?) {
        // Notifications that require no response (e.g. notifications/initialized).
        // Log to stderr for diagnostics; never write to stdout.
        fputs("[curfew-mcp] notification: \(method)\n", stderr)
    }

    // MARK: - Response builders

    private func successResponse(rawID: Any?, result: [String: Any]) -> String {
        serialize(["jsonrpc": "2.0", "id": rawID ?? NSNull(), "result": result])
    }

    private func errorResponse(rawID: Any?, code: Int, message: String) -> String {
        serialize([
            "jsonrpc": "2.0",
            "id": rawID ?? NSNull(),
            "error": ["code": code, "message": message] as [String: Any]
        ])
    }

    private func serialize(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
            return "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Serialisation failed\"}}"
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func writeLine(_ line: String) {
        print(line)
        // Flush immediately — stdio is line-buffered in most contexts, but
        // forcing a flush ensures the MCP host receives the response without
        // waiting for the buffer to fill.
        fflush(stdout)
    }
}
