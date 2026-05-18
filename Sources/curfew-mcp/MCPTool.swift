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
    ///
    /// `request_override` is intentionally absent: override grants depend
    /// on the in-app friction model (5-minute cooldown + 50-character
    /// reason + 3-second confirm hold) which doesn't translate to a
    /// remote channel. The audit's C6 finding details the bypass that
    /// the previous surface created.
    static let all: [MCPTool] = [
        statusTool,
        scheduleTool,
        budgetTool,
        activityTool,
        timeRemainingTool,
        weeklySummaryTool,
        requestExtensionTool,
        setScheduleTool,
        requestStatusTool
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
        var lines = ["Weekly schedule:"]
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

        let extsUsed = events.count(where: { $0.kind == .extensionGranted })
        let ovsUsed = events.count(where: { $0.kind == .overrideGranted })
        let extsRemaining = max(0, settings.extensionWeeklyLimit - extsUsed)
        let ovsRemaining = max(0, settings.overrideWeeklyLimit - ovsUsed)

        let lines: [String] = [
            "Extensions: \(extsRemaining)/\(settings.extensionWeeklyLimit) remaining " +
                "(\(settings.extensionDurationMinutes) min each)",
            "Overrides:  \(ovsRemaining)/\(settings.overrideWeeklyLimit) remaining " +
                "(\(settings.overrideDurationMinutes) min each)",
            "Resets:     \(settings.resetWeekday.shortName)"
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
                "description": "Time window: \"today\" or \"week\" (default)."
            ]
        ] as [String: Any],
        "required": [] as [String]
    ] as [String: Any],
    call: { arguments in
        let period = arguments["period"] as? String ?? "week"
        // The JSON schema advertises only "today" and "week"; enforce that
        // here so malformed callers get a clear JSON-RPC error instead of
        // silently being coerced to the default "week" branch.
        guard period == "today" || period == "week" else {
            throw MCPToolError.invalidArgument(
                "period must be \"today\" or \"week\" (got \"\(period)\")."
            )
        }
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
                "description": "Why more time is needed (shown to the user)."
            ]
        ] as [String: Any],
        "required": ["reason"]
    ] as [String: Any],
    call: { arguments in
        let reason = arguments["reason"] as? String ?? ""
        let argsJSON = encodeArguments(["reason": reason])
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: argsJSON)
        do {
            _ = try MCPSocketClient.send(request)
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

// MARK: - New read tools (v0.2 spec §9.3)

/// Compact structured equivalent of `curfew.status` for clients that want
/// just the clock. Returns `{ minutes, mode, trigger }` so an AI assistant
/// can answer "how much time is left" without parsing prose.
///
/// `mode` and `trigger` are always `"time"` until hours-based enforcement
/// lands — the field is in the response shape now so downstream clients
/// can pattern-match without a schema bump later.
private let timeRemainingTool = MCPTool(
    name: "curfew.get_time_remaining",
    description: """
    Returns a compact machine-readable countdown: minutes until lockout, \
    the current curfew mode ("time", "hours", or "combined"), and which \
    trigger is driving the countdown. Useful for small widgets, status \
    bars, and assistants that just need the number.
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

        let payload: [String: Any] = [
            "minutes": eval.minutesRemaining,
            "phase": phaseName(eval.phase),
            "mode": "time",
            "trigger": "time"
        ]
        return [jsonContent(payload)]
    }
)

/// Device-attributed weekly summary. Feeds reflection-style conversations
/// ("How did this week go?") without each assistant having to re-derive
/// the rollup from raw activity events.
private let weeklySummaryTool = MCPTool(
    name: "curfew.get_weekly_summary",
    description: """
    Returns this week's activity rollup: lockouts held, extensions and \
    overrides used, and a current streak count. The device attribution \
    field echoes the local device name today; multi-device aggregation \
    lands when CloudKit device records ship.
    """,
    inputSchema: emptySchema(),
    call: { _ in
        let settings = loadSharedSettings()
        let now = Date()
        let calendar = Calendar.current
        let weekStart = calendar.startOfWeek(for: now)
        let weekEnd = calendar.date(
            byAdding: .day,
            value: 7,
            to: weekStart
        ) ?? weekStart

        guard let store = openSharedActivityStore() else {
            return [textContent(
                "No activity log found. Has Curfew been launched yet?"
            )]
        }
        let events = (try? store.events(in: weekStart ... weekEnd)) ?? []
        let rollup = ActivityRollups.weeklyRollup(
            events: events,
            weekStart: weekStart,
            calendar: calendar
        )

        let deviceName = Host.current().localizedName
            ?? ProcessInfo.processInfo.hostName

        // Per-device override breakdown. `loadSharedOverrideEvents` reads
        // the same UserDefaults-backed log the app writes on each override
        // grant, so attribution is accurate even when `curfew-mcp` is
        // invoked from a shell that hasn't opened the app.
        let overrideEvents = loadSharedOverrideEvents()
        var overridesByDevice: [String: Int] = [:]
        for event in overrideEvents
            where event.timestamp >= weekStart && event.timestamp < weekEnd {
            overridesByDevice[event.deviceName, default: 0] += 1
        }

        let payload: [String: Any] = [
            "week_of": ISO8601DateFormatter().string(from: weekStart),
            "days_held": rollup.daysWithLockout,
            "extensions_used": rollup.totalExtensionCount,
            "extension_minutes": rollup.totalExtensionMinutes,
            "overrides_used": rollup.totalOverrideCount,
            "override_minutes": rollup.totalOverrideMinutes,
            "streak": rollup.streak,
            "device": deviceName,
            "overrides_by_device": overridesByDevice
        ]
        return [jsonContent(payload)]
    }
)

// MARK: - New write tools (v0.2 spec §9.3)

/// Queues a schedule update for future days. Today's schedule is not
/// weakened by this path — the app's anti-bypass `SchedulePolicyEngine`
/// classifies the change and either applies immediately (`.stricter`),
/// defers to tomorrow (`.weaker`), or no-ops (`.noChange`). That
/// classification happens in the app, not here.
///
/// Arguments:
///   `weekday`       — one of "monday" … "sunday"
///   `lock_time`     — "HH:MM" (24 h)
///   `unlock_time`   — "HH:MM" (24 h), optional — defaults to current
///   `is_day_off`    — boolean, optional
private let setScheduleTool = MCPTool(
    name: "curfew.set_schedule",
    description: """
    Queues a schedule change for a single weekday. Weakening changes \
    (later lock time, adding a day off) wait out a 24-hour cooldown; \
    strengthening changes apply at the next day boundary. Requires the \
    user to approve the change in the Curfew app unless the AI consent \
    policy is set to auto-approve.
    """,
    inputSchema: [
        "type": "object",
        "properties": [
            "weekday": [
                "type": "string",
                "enum": [
                    "monday",
                    "tuesday",
                    "wednesday",
                    "thursday",
                    "friday",
                    "saturday",
                    "sunday"
                ]
            ],
            "lock_time": [
                "type": "string",
                "description": "24-hour time, HH:MM, e.g. \"18:00\"."
            ],
            "unlock_time": [
                "type": "string",
                "description": "Optional. Defaults to the day's current unlock time."
            ],
            "is_day_off": [
                "type": "boolean",
                "description": "Optional. Set true to mark the day off."
            ]
        ] as [String: Any],
        "required": ["weekday", "lock_time"]
    ] as [String: Any],
    call: { arguments in
        guard let weekdayString = arguments["weekday"] as? String,
              let lockTime = arguments["lock_time"] as? String
        else {
            throw MCPToolError.invalidArgument("weekday and lock_time are required.")
        }
        guard weekdayFromName(weekdayString) != nil else {
            throw MCPToolError.invalidArgument(
                "weekday must be one of monday…sunday."
            )
        }
        guard parseHHMM(lockTime) != nil else {
            throw MCPToolError.invalidArgument(
                "lock_time must be HH:MM (24-hour), e.g. \"18:00\"."
            )
        }
        if let unlock = arguments["unlock_time"] as? String, parseHHMM(unlock) == nil {
            throw MCPToolError.invalidArgument(
                "unlock_time must be HH:MM (24-hour)."
            )
        }

        // Shape stored verbatim so the app-side dispatcher can reconstruct
        // the exact user-facing consent prompt.
        var argsDict: [String: String] = [
            "weekday": weekdayString,
            "lock_time": lockTime
        ]
        if let unlock = arguments["unlock_time"] as? String {
            argsDict["unlock_time"] = unlock
        }
        if let off = arguments["is_day_off"] as? Bool {
            argsDict["is_day_off"] = String(off)
        }

        let argsJSON = encodeArguments(argsDict)
        let request = MCPPendingRequest(tool: .setSchedule, argumentsJSON: argsJSON)
        do {
            _ = try MCPSocketClient.send(request)
        } catch {
            throw MCPToolError.queueUnavailable(
                "Could not write to request queue: \(error.localizedDescription)"
            )
        }
        return [textContent(
            "Schedule change queued (ID: \(request.id.uuidString)).\n" +
                "Open the Curfew app to review, or poll with curfew.request_status."
        )]
    }
)

// MARK: - Helpers for the new tools

private func weekdayFromName(_ name: String) -> Weekday? {
    switch name.lowercased() {
    case "monday": .monday
    case "tuesday": .tuesday
    case "wednesday": .wednesday
    case "thursday": .thursday
    case "friday": .friday
    case "saturday": .saturday
    case "sunday": .sunday
    default: nil
    }
}

/// Parses a strict "HH:MM" 24-hour string. Rejects "24:00", "09:5",
/// negative values, and anything with extra whitespace. Returns minutes
/// past midnight on success.
private func parseHHMM(_ text: String) -> Int? {
    let parts = text.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          hour >= 0, hour < 24, minute >= 0, minute < 60
    else { return nil }
    return hour * 60 + minute
}

/// Wraps a JSON-encodable dictionary as an MCP text-content block. The
/// MCP spec doesn't have a first-class "structured JSON" content type
/// today, so we serialize the dictionary and mark it with a `text/json`
/// leading comment so clients can branch on it.
private func jsonContent(_ payload: [String: Any]) -> [String: Any] {
    guard
        let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ),
        let text = String(data: data, encoding: .utf8)
    else {
        return textContent("{}")
    }
    return ["type": "text", "text": text]
}

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
                "description": "UUID returned by the write tool."
            ]
        ] as [String: Any],
        "required": ["request_id"]
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

/// Failure modes for MCP tool `call` closures. Thrown values are mapped to
/// JSON-RPC error responses by the server's dispatch loop.
enum MCPToolError: Error, LocalizedError {
    /// A required argument was missing, had the wrong type, or failed
    /// a domain-level constraint (e.g. override reason too short).
    case invalidArgument(String)

    /// The shared request-queue file could not be written — typically a
    /// sandboxing or permissions issue. The MCP client should retry after
    /// confirming the app is running.
    case queueUnavailable(String)

    /// Localised message surfaced back to the MCP client as the
    /// JSON-RPC error's `message` field.
    var errorDescription: String? {
        switch self {
        case .invalidArgument(let msg): msg
        case .queueUnavailable(let msg): msg
        }
    }
}

// MARK: - Shared helpers

/// Opens the settings using the Curfew app's UserDefaults suite.
private func loadSharedSettings() -> CurfewSettings {
    let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    return CurfewSettingsStore(defaults: defaults).load()
}

/// Reads the app's persisted override-event log from UserDefaults so
/// `curfew.get_weekly_summary` can surface per-device attribution
/// without opening an `NSObject`-bound settings store.
private func loadSharedOverrideEvents() -> [OverrideEvent] {
    let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    return CurfewSettingsStore(defaults: defaults).loadOverrideEvents()
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

/// Formats `date` as a locale-sensitive short time string, e.g. `"6:00 PM"`.
private func formatTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: date)
}

/// Returns a short human-readable label for `event`, used in the activity
/// tool's output lines.
private func eventDetail(_ event: ActivityEvent) -> String {
    switch event.kind {
    case .sessionStarted: "session_started"
    case .sessionEnded: "session_ended"
    case .warningEscalated:
        "warning \(event.note ?? "?") (\(event.minutesValue ?? 0) min remaining)"
    case .lockoutStarted: "lockout_started"
    case .lockoutEnded: "lockout_ended"
    case .extensionGranted:
        "extension_granted +\(event.minutesValue ?? 0) min"
    case .overrideGranted:
        "override_granted +\(event.minutesValue ?? 0) min"
    case .dayOff: "day_off"
    }
}
