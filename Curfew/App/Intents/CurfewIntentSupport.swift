import AppIntents
import CurfewKit
import Foundation

/// Shared plumbing for Curfew's App Intents surface (Shortcuts, Spotlight,
/// Siri).
///
/// The intents reuse the same observed-status store and signed write queue as
/// `curfew-mcp` and `curfew-ctl`, rather than guessing from saved rules:
///
/// * **Reads** load only a fresh app-observed status; stale or absent state is
///   unknown, never proof that an independently authorized lock is absent.
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
        CurfewSettingsStore.production().load()
    }

    /// A schedule-only forecast used to test weekly-consent interpretation.
    /// User-facing status intents must use `currentObservedStatus` instead:
    /// a fixed-duration remote lock or a durable deadline is not a saved rule.
    static func currentEvaluation(
        at date: Date = Date(),
        settingsStore: CurfewSettingsStore? = nil,
        flavor: CurfewFlavor = .current
    ) -> CurfewEvaluation {
        let store = settingsStore ?? CurfewSettingsStore.production()
        let settings = store.load()
        let enabled = AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: store.loadAutomaticScheduleConsent(),
            hasCompletedInitialSetup: settings.hasCompletedInitialSetup,
            flavor: flavor
        )
        let engine = CurfewEnforcementEngine()
        return engine.evaluate(
            at: date,
            schedule: enabled ? settings.schedule : .allDaysOff,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )
    }

    /// Reads the same fresh, app-settled status as the local MCP and CLI.
    static func currentObservedStatus(
        at date: Date = Date(),
        store: CurfewObservedStatusStore = CurfewObservedStatusStore()
    ) -> CurfewObservedStatus? {
        store.loadFresh(at: date)
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

    /// A stale observation never becomes a false claim that the Mac is free.
    static func statusSummary(_ status: CurfewObservedStatus?) -> String {
        guard let status else { return IntentCopy.notCheckedIn }
        switch status.phase {
        case "locked":
            return IntentCopy.locked(unlockTime: status.unlockDate.map(formatTime))
        case "day_off":
            return IntentCopy.dayOff
        case "working", "warning":
            guard let minutes = status.minutesRemaining else { return IntentCopy.notCheckedIn }
            return countdownLine(minutes: minutes, curfewTime: status.lockDate.map(formatTime))
        default:
            return status.availabilityDescription
        }
    }

    /// "3 hours 30 minutes until curfew at 6:00 PM."
    static func countdownLine(minutes: Int, curfewTime: String?) -> String {
        let duration = durationText(minutes: minutes)
        guard let curfewTime else { return "\(duration) until curfew." }
        return "\(duration) until curfew at \(curfewTime)."
    }

    /// Spoken hours and minutes: "3 hours 30 minutes", "1 hour", "45 minutes".
    static func durationText(minutes: Int) -> String {
        let hours = max(minutes, 0) / 60
        let rest = max(minutes, 0) % 60
        func unit(_ value: Int, _ name: String) -> String {
            "\(value) \(name)\(value == 1 ? "" : "s")"
        }
        switch (hours, rest) {
        case (0, _): return unit(rest, "minute")
        case (_, 0): return unit(hours, "hour")
        default: return "\(unit(hours, "hour")) \(unit(rest, "minute"))"
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

    /// No fresh app observation exists for a reliable countdown.
    case statusUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .queueUnavailable:
            "Couldn't reach Curfew. Open it once, then try again."
        case .invalidLockTime:
            "That time isn't valid. Pick a time of day."
        case .statusUnavailable:
            LocalizedStringResource(stringLiteral: IntentCopy.notCheckedIn)
        }
    }
}

/// Every line Siri and Shortcuts say for Curfew, in the product's words.
enum IntentCopy {
    static let notCheckedIn = "Curfew hasn't checked in. Open it to see where things stand."
    static let dayOff = "Day off. No curfew today."
    static let moreTimeAsked = "Asked. Approve it in Curfew."
    static let overrideOpened = "Overrides only happen in Curfew. It's open. Make your case there."

    static func locked(unlockTime: String?) -> String {
        guard let unlockTime else { return "Locked." }
        return "Locked. Unlocks at \(unlockTime)."
    }

    static func scheduleAsked(weekday: String, curfewTime: String?, isDayOff: Bool) -> String {
        if isDayOff || curfewTime == nil {
            return "Asked for \(weekday) as a day off. Approve it in Curfew."
        }
        return "Asked for curfew at \(curfewTime ?? "") on \(weekday). Approve it in Curfew."
    }
}
