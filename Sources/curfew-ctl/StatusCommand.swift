import ArgumentParser
import CurfewKit
import Foundation

/// Prints the current enforcement phase and time remaining.
///
/// Reads settings from the Curfew app's UserDefaults domain — no IPC
/// required, so this works whether or not the app is running.
struct StatusCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current enforcement phase and time remaining."
    )

    /// When true, emit a single JSON object suitable for piping to `jq`
    /// or reading from other tools.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    func run() {
        let settings = loadSettings()
        let now = Date()
        let engine = CurfewEnforcementEngine()
        let eval = engine.evaluate(
            at: now,
            schedule: settings.schedule,
            extensionMinutesGrantedToday: 0,
            overrideUntil: nil,
            warningIntervals: settings.warningIntervals
        )

        if json {
            printJSON(eval: eval, now: now, settings: settings)
        } else {
            printPlain(eval: eval, now: now, settings: settings)
        }
    }

    // MARK: - Output formatters

    private func printPlain(
        eval: CurfewEvaluation,
        now: Date,
        settings: CurfewSettings
    ) {
        print("phase:     \(phaseName(eval.phase))")

        if eval.phase == .locked || eval.phase == .dayOff {
            if let unlock = eval.unlockDate {
                print("unlocks:   \(formatTime(unlock))")
            }
        } else {
            print("remaining: \(eval.minutesRemaining) min")
            if let lock = eval.lockDate {
                print("locks at:  \(formatTime(lock))")
            }
        }

        if eval.warningStage != .none {
            print("warning:   \(eval.warningStage)")
        }
    }

    private func printJSON(
        eval: CurfewEvaluation,
        now: Date,
        settings: CurfewSettings
    ) {
        var obj: [String: Any] = [
            "phase": phaseName(eval.phase),
            "minutes_remaining": eval.minutesRemaining,
            "warning_stage": warningStageString(eval.warningStage),
            "can_request_extension": eval.canRequestExtension,
        ]
        if let lock = eval.lockDate {
            obj["lock_date"] = iso8601(lock)
        }
        if let unlock = eval.unlockDate {
            obj["unlock_date"] = iso8601(unlock)
        }
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

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func warningStageString(_ stage: WarningStage) -> String {
        switch stage {
        case .none: return "none"
        case .thirtyMinutes: return "T-30"
        case .fifteenMinutes: return "T-15"
        case .fiveMinutes: return "T-5"
        case .twoMinutes: return "T-2"
        case .oneMinute: return "T-1"
        case .lockout: return "lockout"
        }
    }
}
