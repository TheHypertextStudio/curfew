import AppIntents
import CurfewKit
import Foundation

/// Shared plumbing for Curfew's App Intents surface (Shortcuts, Spotlight,
/// Siri).
///
/// The intents deliberately reuse the *exact* code paths the MCP tool surface
/// (`curfew-mcp`) and the bundled CLI (`curfew-ctl`) use — they are a third
/// front-end onto the same shared storage, not a parallel data path:
///
/// * **Reads** open the app's `UserDefaults` suite by name
///   (``SharedPaths/defaultsSuiteName``), load `CurfewSettings` through
///   `CurfewSettingsStore`, and evaluate with `CurfewEnforcementEngine` — the
///   same three steps `MCPTool.statusTool` / `timeRemainingTool` perform.
/// * **Writes** build a signed ``MCPPendingRequest`` and hand it to
///   ``MCPSocketClient/send(_:)`` (which appends to ``MCPRequestQueue``),
///   identical to the MCP write tools. The running app's `MCPRequestMonitor`
///   then surfaces the same consent sheet. There is **no** auto-approve
///   bypass here: the intent only enqueues; the user (or their configured
///   consent policy) decides.
enum CurfewIntentSupport {
    /// Loads the shared settings the same way `curfew-mcp` does: through the
    /// app's `UserDefaults` suite, decoded by `CurfewSettingsStore`.
    static func loadSharedSettings() -> CurfewSettings {
        let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
        return CurfewSettingsStore(defaults: defaults).load()
    }

    /// Evaluates the current enforcement state with the identical arguments
    /// the MCP read tools pass (`extensionMinutesGrantedToday: 0`,
    /// `overrideUntil: nil`). The intents are a read-through onto shared
    /// storage, so they intentionally do not reach into the running app's
    /// live in-memory extension/override counters — they report the
    /// schedule-derived state exactly as the MCP surface does.
    static func currentEvaluation(at date: Date = Date()) -> CurfewEvaluation {
        let settings = loadSharedSettings()
        let engine = CurfewEnforcementEngine()
        return engine.evaluate(
            at: date,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )
    }

    /// Builds, signs, and enqueues a write request exactly like the MCP write
    /// tools (`MCPTool.requestExtensionTool` / `setScheduleTool`). Returns the
    /// new request's ID so the dialog can echo it back, mirroring the MCP
    /// tools' "queued (ID: …)" response.
    ///
    /// Signing uses ``MCPRequestSigner`` so the app can authenticate the
    /// request under the user's configured consent policy; an unsigned or
    /// forged request always falls through to the consent sheet (see
    /// `CurfewAppModel.handleNewMCPRequests`).
    @discardableResult
    static func enqueueWriteRequest(
        tool: MCPWriteTool,
        arguments: [String: String]
    ) throws -> UUID {
        let argsJSON = encodeArguments(arguments)
        var request = MCPPendingRequest(tool: tool, argumentsJSON: argsJSON)
        request.signature = MCPRequestSigner.sign(request)
        do {
            _ = try MCPSocketClient.send(request)
        } catch {
            throw CurfewIntentError.queueUnavailable
        }
        return request.id
    }

    /// JSON-encodes `arguments` to the compact, sorted-key string the queue
    /// stores. Matches `MCPTool.encodeArguments` so the app-side dispatcher
    /// reconstructs the same payload regardless of which front-end queued it.
    static func encodeArguments(_ args: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Human-readable, present-tense summary of an evaluation for an intent
    /// dialog, e.g. `"You're in your work session — 42 minutes until curfew."`
    static func statusSummary(_ eval: CurfewEvaluation) -> String {
        switch eval.phase {
        case .locked:
            if let unlock = eval.unlockDate {
                return "Curfew is active. Unlocks at \(formatTime(unlock))."
            }
            return "Curfew is active."
        case .dayOff:
            return "No curfew today — enjoy your day off."
        case .working, .warning:
            let minutes = eval.minutesRemaining
            let noun = minutes == 1 ? "minute" : "minutes"
            if let lock = eval.lockDate {
                return "Work session active — \(minutes) \(noun) until curfew at \(formatTime(lock))."
            }
            return "Work session active — \(minutes) \(noun) until curfew."
        }
    }

    /// Locale-sensitive short time string (e.g. `"6:00 PM"`), matching the
    /// MCP status tool's `formatTime`.
    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

/// User-visible failure modes for Curfew's App Intents. Conforms to
/// `CustomLocalizedStringResourceConvertible` so Shortcuts/Siri surface the
/// message rather than a generic "the action failed".
enum CurfewIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The shared request queue could not be written (sandbox/permissions).
    case queueUnavailable

    /// A supplied "HH:MM" lock time was malformed or out of range.
    case invalidLockTime

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .queueUnavailable:
            "Couldn't reach Curfew's request queue. Make sure Curfew has been launched once."
        case .invalidLockTime:
            "That lock time isn't valid. Use a time of day between 00:00 and 23:59."
        }
    }
}
