import ArgumentParser
import CurfewKit
import Foundation

/// Prints the active weekly schedule.
struct ScheduleCommand: ParsableCommand {
    /// ArgumentParser command metadata.
    static var configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Show the active weekly schedule."
    )

    /// Emit JSON rather than the default human-readable format.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    /// Entry point — reads settings and prints the weekly schedule.
    func run() {
        let settings = loadSettings()
        if json {
            printJSON(settings: settings)
        } else {
            printPlain(settings: settings)
        }
    }

    // MARK: - Output formatters

    private func printPlain(settings: CurfewSettings) {
        for weekday in Weekday.allCases {
            let rule = settings.schedule.rule(for: weekday)
            if rule.isDayOff {
                print("\(weekday.shortName): day off")
                continue
            }
            let lockStr = minutesToHHMM(rule.lockMinutes)
            let unlockStr = minutesToHHMM(rule.unlockMinutes)
            print("\(weekday.shortName): \(lockStr) → \(unlockStr)")
        }

        if let pending = settings.pendingScheduleChange {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            print("\nPending change effective: \(fmt.string(from: pending.effectiveAt))")
        }
    }

    private func printJSON(settings: CurfewSettings) {
        var days: [[String: Any]] = []
        for weekday in Weekday.allCases {
            let rule = settings.schedule.rule(for: weekday)
            if rule.isDayOff {
                days.append(["day": weekday.shortName, "day_off": true])
                continue
            }
            days.append([
                "day": weekday.shortName,
                "day_off": false,
                "lock": minutesToHHMM(rule.lockMinutes),
                "unlock": minutesToHHMM(rule.unlockMinutes)
            ])
        }
        let obj: [String: Any] = ["days": days]
        if let data = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
    }
}
