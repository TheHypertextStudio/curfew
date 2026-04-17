import CurfewKit
import Foundation

/// A single tool exposed by `curfew-mcp`. Tools map directly to MCP
/// `tools/list` entries and `tools/call` handlers.
///
/// Each tool is responsible for reading shared storage and returning content
/// that the MCP client (Claude, Cursor, …) can interpret.
struct MCPTool {
    /// Stable identifier sent in `tools/list` and matched in `tools/call`.
    let name: String

    /// Human-readable description shown to the AI model in `tools/list`.
    let description: String

    /// JSON Schema object describing the tool's `arguments` payload.
    let inputSchema: [String: Any]

    /// Invoked with the parsed arguments from `tools/call params.arguments`.
    /// Returns an array of MCP content objects (each `{"type":"text","text":"…"}`).
    /// Throws on unrecoverable errors; the server maps throws to JSON-RPC errors.
    let call: (_ arguments: [String: Any]) throws -> [[String: Any]]

    /// All tools registered in the server. Append new tools here; order
    /// determines the listing sent to the client.
    static let all: [MCPTool] = [
        statusTool,
        scheduleTool,
        budgetTool,
        activityTool,
        requestExtensionTool,
        requestOverrideTool,
        requestStatusTool,
    ]
}

// MARK: - Read tools

private let statusTool = MCPTool(
    name: "curfew.status",
    description: """
    Returns the current Curfew enforcement status: phase (working, warning, \
    locked, day_off), minutes remaining until lock, today's schedule window, \
    and whether an extension can be requested right now.
    """,
    inputSchema: emptySchema(),
    call: { _ in
        let settings = loadSharedSettings()
        let now = Date()
        let engine = CurfewEnforcementEngine()
        let eval = engine.evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )

        var lines: [String] = []
        lines.append("Phase: \(phaseName(eval.phase))")

        switch eval.phase {
        case .locked:
            if let unlock = eval.unlockDate {
                lines.append("Unlocks: \(formatTime(unlock))")
            }
        case .dayOff:
            lines.append("No curfew today.")
        default:
            lines.append("Minutes remaining: \(eval.minutesRemaining)")
            if let lock = eval.lockDate {
                lines.append("Locks at: \(formatTime(lock))")
            }
            if eval.warningStage != .none {
                lines.append("Warning stage: \(eval.warningStage)")
            }
        }

        lines.append("Can request extension: \(eval.canRequestExtension ? "yes" : "no")")
        return [textContent(lines.joined(separator: "\n"))]
    }
)

private let scheduleTool = MCPTool(
    name: "curfew.schedule",
    description: """
    Returns the full weekly Curfew schedule: per-day lock and unlock times, \
    which days are marked as day-off, and any pending schedule change that \
    is waiting out a 24-hour anti-bypass cooldown.
    """,
    inputSchema: emptySchema(),
    call: { _ in
        let settings = loadSharedSettings()
        var lines: [String] = ["Weekly schedule:"]
        for weekday in Weekday.allCases {
            let rule = settings.schedule.rule(for: weekday)
            if rule.isDayOff {
                lines.append("  \(weekday.shortName): day off")
            } else {
                let lock = minutesToHHMM(rule.lockMinutes)
                let unlock = minutesToHHMM(rule.unlockMinutes)
                lines.append("  \(weekday.shortName): \(lock) → \(unlock)")
            }
        }
        if let pending = settings.pendingScheduleChange {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            lines.append("Pending change effective: \(fmt.string(from: pending.effectiveAt))")
        }
        return [textContent(lines.joined(separator: "\n"))]
    }
)

private let budgetTool = MCPTool(
    name: "curfew.budget",
    description: """
    Returns this week's extension and override budget: weekly limits, how many \
    have been used so far, remaining slots, and duration per slot. Useful for \
    deciding whether to request an extension or escalate to an override.
    """,
    inputSchema: emptySchema(),
    call: { _ in
        let settings = loadSharedSettings()
        let now = Date()
        let weekStart = Calendar.current.startOfWeek(for: now)
        let store = openSharedActivityStore()
        let events = (try? store?.events(in: weekStart ... now)) ?? []

        let extsUsed = events.filter { $0.kind == .extensionGranted }.count
        let ovsUsed = events.filter { $0.kind == .overrideGranted }.count
        let extsRemaining = max(0, settings.extensionWeeklyLimit - extsUsed)
        let ovsRemaining = max(0, settings.overrideWeeklyLimit - ovsUsed)

        let lines: [String] = [
            "Extensions: \(extsRemaining)/\(settings.extensionWeeklyLimit) remaining " +
                "(\(settings.extensionDurationMinutes) min each)",
            "Overrides:  \(ovsRemaining)/\(settings.overrideWeeklyLimit) remaining " +
                "(\(settings.overrideDurationMinutes) min each)",
            "Resets:     \(settings.resetWeekday.shortName)",
        ]
        return [textContent(lines.joined(separator: "\n"))]
    }
)

private let activityTool = MCPTool(
    name: "curfew.activity",
    description: """
    Returns recent activity events from the local log. Pass \
    `{"period": "today"}` to limit to today's events or \
    `{"period": "week"}` (default) for the full current week.
    """,
    inputSchema: [
        "type": "object",
        "properties": [
            "period": [
                "type": "string",
                "enum": ["today", "week"],
                "description": "Time window: \"today\" or \"week\" (default).",
            ],
        ] as [String: Any],
        "required": [] as [String],
    ] as [String: Any],
    call: { arguments in
        let period = arguments["period"] as? String ?? "week"
        let now = Date()
        let calendar = Calendar.current
        let rangeStart: Date = period == "today"
            ? calendar.startOfDay(for: now)
            : calendar.startOfWeek(for: now)

        guard let store = openSharedActivityStore() else {
            return [textContent("No activity log found. Has Curfew been launched yet?")]
        }
        let events = (try? store.events(in: rangeStart ... now)) ?? []
        guard !events.isEmpty else {
            return [textContent("No events for \(period).")]
        }

        let iso = ISO8601DateFormatter()
        let lines = events.reversed().map { event -> String in
            let time = iso.string(from: event.timestamp)
            let detail = eventDetail(event)
            return "  \(time)  \(detail)"
        }
        return [textContent("Activity (\(period)):\n" + lines.joined(separator: "\n"))]
    }
)

// MARK: - Write tools

private let requestExtensionTool = MCPTool(
    name: "curfew.request_extension",
    description: """
    Queues a request for a work-session extension (default +15 min). The \
    Curfew app will show the user a consent prompt; extensions are only \
    granted during warning stages (T-30 and T-15). Returns a request ID \
    you can poll with `curfew.request_status`.
    """,
    inputSchema: [
        "type": "object",
        "properties": [
            "reason": [
                "type": "string",
                "description": "Why more time is needed (shown to the user).",
            ],
        ] as [String: Any],
        "required": ["reason"],
    ] as [String: Any],
    call: { arguments in
        let reason = arguments["reason"] as? String ?? ""
        let argsJSON = encodeArguments(["reason": reason])
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: argsJSON)
        do {
            try MCPRequestQueue.append(request)
        } catch {
            throw MCPToolError.queueUnavailable(
                "Could not write to request queue: \(error.localizedDescription)"
            )
        }
        return [textContent(
            "Extension request queued (ID: \(request.id.uuidString)).\n" +
            "Open the Curfew app to approve, or poll with curfew.request_status."
        )]
    }
)

private let requestOverrideTool = MCPTool(
    name: "curfew.request_override",
    description: """
    Queues a "Convince Me" override request. If approved by the user, Curfew \
    temporarily suspends the lockout for the configured override duration \
    (default 30 min). Requires a justification of at least 50 characters. \
    Returns a request ID to poll with `curfew.request_status`.
    """,
    inputSchema: [
        "type": "object",
        "properties": [
            "reason": [
                "type": "string",
                "description": "Justification for the override (min 50 characters).",
            ],
        ] as [String: Any],
        "required": ["reason"],
    ] as [String: Any],
    call: { arguments in
        let reason = arguments["reason"] as? String ?? ""
        guard reason.count >= 50 else {
            throw MCPToolError.invalidArgument(
                "Override reason must be at least 50 characters (got \(reason.count))."
            )
        }
        let argsJSON = encodeArguments(["reason": reason])
        let request = MCPPendingRequest(tool: .requestOverride, argumentsJSON: argsJSON)
        do {
            try MCPRequestQueue.append(request)
        } catch {
            throw MCPToolError.queueUnavailable(
                "Could not write to request queue: \(error.localizedDescription)"
            )
        }
        return [textContent(
            "Override request queued (ID: \(request.id.uuidString)).\n" +
            "Open the Curfew app to review, or poll with curfew.request_status."
        )]
    }
)

private let requestStatusTool = MCPTool(
    name: "curfew.request_status",
    description: """
    Returns the current approval status for a pending MCP write request. \
    Pass the `request_id` returned by `curfew.request_extension` or \
    `curfew.request_override`. Status is one of: pending, approved, denied.
    """,
    inputSchema: [
        "type": "object",
        "properties": [
            "request_id": [
                "type": "string",
                "description": "UUID returned by the write tool.",
            ],
        ] as [String: Any],
        "required": ["request_id"],
    ] as [String: Any],
    call: { arguments in
        guard let idString = arguments["request_id"] as? String,
              let id = UUID(uuidString: idString) else {
            throw MCPToolError.invalidArgument("Invalid request_id UUID.")
        }
        let requests = MCPRequestQueue.load()
        guard let request = requests.first(where: { $0.id == id }) else {
            return [textContent("Request \(idString) not found (may have been pruned).")]
        }
        var lines = ["Status: \(request.status.rawValue)"]
        if let resolved = request.resolvedAt {
            lines.append("Resolved at: \(ISO8601DateFormatter().string(from: resolved))")
        }
        if let denial = request.denialReason {
            lines.append("Denial reason: \(denial)")
        }
        return [textContent(lines.joined(separator: "\n"))]
    }
)

// MARK: - Errors

enum MCPToolError: Error, LocalizedError {
    case invalidArgument(String)
    case queueUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let msg): return msg
        case .queueUnavailable(let msg): return msg
        }
    }
}

// MARK: - Shared helpers

/// Opens the settings using the Curfew app's UserDefaults suite.
private func loadSharedSettings() -> CurfewSettings {
    let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    return CurfewSettingsStore(defaults: defaults).load()
}

/// Opens the shared activity SQLite database. Returns nil when the app
/// hasn't been launched yet.
private func openSharedActivityStore() -> ActivityStore? {
    guard FileManager.default.fileExists(
        atPath: SharedPaths.activityDatabase.path
    ) else {
        return nil
    }
    return try? ActivityStore(databaseURL: SharedPaths.activityDatabase)
}

/// Wraps a plain text string in an MCP content object.
private func textContent(_ text: String) -> [String: Any] {
    ["type": "text", "text": text]
}

/// Empty JSON Schema for tools that take no arguments.
private func emptySchema() -> [String: Any] {
    ["type": "object", "properties": [String: Any](), "required": [String]()]
}

/// JSON-encodes `arguments` to a compact string for storage in the queue.
private func encodeArguments(_ args: [String: String]) -> String {
    let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

private func formatTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: date)
}

private func eventDetail(_ event: ActivityEvent) -> String {
    switch event.kind {
    case .sessionStarted: return "session_started"
    case .sessionEnded: return "session_ended"
    case .warningEscalated:
        return "warning \(event.note ?? "?") (\(event.minutesValue ?? 0) min remaining)"
    case .lockoutStarted: return "lockout_started"
    case .lockoutEnded: return "lockout_ended"
    case .extensionGranted:
        return "extension_granted +\(event.minutesValue ?? 0) min"
    case .overrideGranted:
        return "override_granted +\(event.minutesValue ?? 0) min"
    case .dayOff: return "day_off"
    }
}

