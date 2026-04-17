import ArgumentParser
import CurfewKit
import Foundation

/// Enqueues a "Convince Me" override request for the running Curfew app to
/// approve or deny. The CLI never mutates enforcement state directly —
/// writes always flow through the same consent queue the MCP server uses,
/// so an unattended shell session can't bypass the review sheet that a
/// foreground session would see.
///
/// The queue file lives at ``SharedPaths.mcpRequestQueue``; the running app
/// observes it via `MCPRequestMonitor` and raises an `MCPConsentSheet`.
struct OverrideCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "override",
        abstract: "Queue an override request for the running app to approve."
    )

    /// Justification shown to the user in the consent sheet. Mirrors the
    /// 50-character minimum enforced by the in-app "Convince Me" form and
    /// the `curfew.request_override` MCP tool, so all three paths feel the
    /// same and the Override log stays consistent.
    @Argument(help: "Reason for the override (minimum 50 characters).")
    var reason: String

    /// Opt-in JSON output so scripts can parse the request ID without
    /// brittle string matching.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    func run() throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let minChars = OverrideRequestPolicy.minimumJustificationCharacters
        guard trimmed.count >= minChars else {
            throw ValidationError(
                "Override reason must be at least \(minChars) characters "
                    + "(got \(trimmed.count))."
            )
        }

        let argsJSON = encodeArguments(["reason": trimmed])
        let request = MCPPendingRequest(
            tool: .requestOverride,
            argumentsJSON: argsJSON
        )
        do {
            try MCPRequestQueue.append(request)
        } catch {
            throw CleanExit.message(
                "Could not write to request queue: \(error.localizedDescription). " +
                    "Is the Curfew app installed?"
            )
        }

        if json {
            emitJSON(request: request)
        } else {
            emitPlain(request: request)
        }
    }

    private func emitPlain(request: MCPPendingRequest) {
        print("queued:  \(request.id.uuidString)")
        print("status:  pending approval in the Curfew app")
    }

    private func emitJSON(request: MCPPendingRequest) {
        let obj: [String: Any] = [
            "request_id": request.id.uuidString,
            "status": "pending",
            "tool": request.tool.rawValue
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            print("{}")
            return
        }
        print(text)
    }

    /// JSON-encodes the argument dictionary the consent sheet reads. Kept
    /// parallel to the identical helper in `curfew-mcp` so the two entry
    /// points produce byte-identical queue entries.
    private func encodeArguments(_ args: [String: String]) -> String {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: args,
                options: [.sortedKeys]
            ),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}
