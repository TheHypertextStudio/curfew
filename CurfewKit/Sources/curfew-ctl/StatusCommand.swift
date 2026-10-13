import ArgumentParser
import CurfewKit
import Foundation

/// Prints the current enforcement phase and time remaining.
///
/// Reads the app's last settled observation without launching it. A missing
/// or stale observation is unknown, never a predicted schedule phase.
struct StatusCommand: ParsableCommand {
    /// ArgumentParser command metadata.
    static var configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current enforcement phase and time remaining."
    )

    /// When true, emit a single JSON object suitable for piping to `jq`
    /// or reading from other tools.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    /// Entry point — prints the last fresh app observation.
    func run() {
        let status = CurfewObservedStatusStore().loadFresh(at: Date())

        if json {
            printJSON(status: status)
        } else {
            printPlain(status: status)
        }
    }

    // MARK: - Output formatters

    private func printPlain(status: CurfewObservedStatus?) {
        print("phase:     \(status?.phase ?? "unknown")")

        if status == nil || status?.phase == "unknown" {
            print(
                "status:    \(status?.availabilityDescription ?? "No recent Curfew status is available.")"
            )
        }
        if let minutes = status?.minutesRemaining {
            print("remaining: \(minutes) min")
        }
        if let lock = status?.lockDate {
            print("locks at:  \(formatTime(lock))")
        }
        if let unlock = status?.unlockDate {
            print("unlocks:   \(formatTime(unlock))")
        }
        if let warning = status?.warningStage, warning != "none" {
            print("warning:   \(warning)")
        }
    }

    static func jsonObject(from status: CurfewObservedStatus?) -> [String: Any] {
        var obj: [String: Any] = [
            "phase": status?.phase ?? "unknown",
            "warning_stage": status?.warningStage ?? "none",
            "can_request_extension": status?.canRequestExtension ?? false
        ]
        if let reason = status?.unavailableReason {
            obj["unavailable_reason"] = reason
        }
        if let mode = status?.mode {
            obj["mode"] = mode
        }
        if let minutes = status?.minutesRemaining {
            obj["minutes_remaining"] = minutes
        }
        if let lock = status?
            .lockDate {
            obj["lock_date"] = ISO8601DateFormatter().string(from: lock)
        }
        if let unlock = status?
            .unlockDate {
            obj["unlock_date"] = ISO8601DateFormatter().string(from: unlock)
        }
        return obj
    }

    private func printJSON(status: CurfewObservedStatus?) {
        let obj = Self.jsonObject(from: status)
        if let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    // MARK: - Formatting helpers

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
