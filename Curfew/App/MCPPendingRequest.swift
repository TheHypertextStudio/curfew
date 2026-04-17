import Foundation

/// A write-tool request queued by `curfew-mcp` for user approval in the
/// Curfew app.
///
/// Lifecycle:
/// 1. `curfew-mcp` creates a `MCPPendingRequest` with `status = .pending`
///    and appends it to ``SharedPaths/mcpRequestQueue``.
/// 2. The Curfew app's `MCPRequestMonitor` detects the new entry and shows
///    a consent sheet.
/// 3. The user approves or denies. The app updates `status` in-place and
///    sets `resolvedAt`.
/// 4. `curfew-mcp` polls the queue file until the entry's `status` changes
///    from `.pending`, then responds to the MCP client accordingly. Timeout
///    after 120 seconds → return a "timed out" error to the client.
public struct MCPPendingRequest: Codable, Equatable, Identifiable {
    /// Stable unique key for this request. Used by `curfew-mcp` to find
    /// its own entry in the queue after a poll cycle.
    public let id: UUID

    /// The write tool that was invoked.
    public let tool: MCPWriteTool

    /// Freeform arguments from the MCP client (tool-specific JSON payload
    /// decoded from the `tools/call` params). Stored verbatim so the app
    /// can reconstruct the exact user-facing prompt.
    public let argumentsJSON: String

    /// ISO 8601 timestamp when `curfew-mcp` added the request.
    public let requestedAt: Date

    /// Approval state. Starts as `.pending`; the app writes `.approved` or
    /// `.denied` after user interaction.
    public var status: MCPRequestStatus

    /// Set by the app when the user resolves the request.
    public var resolvedAt: Date?

    /// Human-readable note the app may attach on denial (e.g. "Not during
    /// lockout"). Nil on approval and on pending requests.
    public var denialReason: String?

    public init(
        id: UUID = UUID(),
        tool: MCPWriteTool,
        argumentsJSON: String,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.argumentsJSON = argumentsJSON
        self.requestedAt = requestedAt
        self.status = .pending
        self.resolvedAt = nil
        self.denialReason = nil
    }
}

/// The MCP write-capable tools. Read tools never queue; they respond
/// inline from shared storage.
public enum MCPWriteTool: String, Codable, CaseIterable {
    /// Grant a short extension to the current session's end time.
    case requestExtension = "curfew.request_extension"

    /// Grant a timed override that lets the user work past curfew.
    case requestOverride = "curfew.request_override"

    /// A human-readable label shown in the consent sheet.
    public var displayName: String {
        switch self {
        case .requestExtension:
            "Extension Request"
        case .requestOverride:
            "Override Request"
        }
    }
}

/// Approval state for an ``MCPPendingRequest``.
public enum MCPRequestStatus: String, Codable, Equatable {
    /// Awaiting user interaction in the Curfew app consent sheet.
    case pending

    /// The user approved the request. `curfew-mcp` should apply the
    /// action and return success to the MCP client.
    case approved

    /// The user denied the request. `curfew-mcp` should return a
    /// user-visible refusal to the MCP client.
    case denied
}
