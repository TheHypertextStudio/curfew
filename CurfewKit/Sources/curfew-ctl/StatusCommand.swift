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
    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    /// Entry point — prints the last fresh app observation.
    func run() throws {
        let status = CurfewObservedStatusStore().loadFresh(at: Date())

        if json {
            try CLIOutput.printJSON(Self.jsonObject(from: status))
        } else {
            try printPlain(status: status)
        }
    }

    // MARK: - Output formatters

    private func printPlain(status: CurfewObservedStatus?) throws {
        var lines = ["Phase: \(status?.phase ?? "unknown")"]

        if status == nil || status?.phase == "unknown" {
            lines.append(status?.availabilityDescription ?? "No recent Curfew status is available.")
        }
        if let minutes = status?.minutesRemaining {
            lines.append("Remaining: \(minutes) min")
        }
        if let lock = status?.lockDate {
            lines.append("Locks at: \(formatTime(lock))")
        }
        if let unlock = status?.unlockDate {
            lines.append("Unlocks at: \(formatTime(unlock))")
        }
        if let warning = status?.warningStage, warning != "none" {
            lines.append("Warning: \(warning)")
        }
        try CLIText.print(lines.joined(separator: "\n"), title: "Curfew status", options: options)
    }

    static func jsonObject(from status: CurfewObservedStatus?) throws -> [String: Any] {
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
            obj["remaining_seconds"] = try CLIOutput.durationSeconds(minutes)
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

    // MARK: - Formatting helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
