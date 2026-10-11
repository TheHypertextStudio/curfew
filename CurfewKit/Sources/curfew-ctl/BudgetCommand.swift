import ArgumentParser
import CurfewKit
import Foundation

/// Prints extension and override budget status.
struct BudgetCommand: ParsableCommand {
    /// ArgumentParser command metadata.
    static var configuration = CommandConfiguration(
        commandName: "budget",
        abstract: "Show extension and override budget remaining this week."
    )

    /// Emit JSON rather than the default human-readable format.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    /// Entry point — reads settings + activity, prints remaining budgets.
    func run() {
        let settings = loadSettings()
        let now = Date()

        let store = openActivityStore()
        let weekStart = Calendar.current.startOfWeek(for: now)
        let events = (try? store?.events(in: weekStart ... now)) ?? []

        let extensionsUsed = events.count(where: { $0.kind == .extensionGranted })
        let overridesUsed = events.count(where: { $0.kind == .overrideGranted })

        let extensionsRemaining = max(0, settings.extensionWeeklyLimit - extensionsUsed)
        let overridesRemaining = max(0, settings.overrideWeeklyLimit - overridesUsed)

        if json {
            let obj: [String: Any] = [
                "extensions": [
                    "used": extensionsUsed,
                    "remaining": extensionsRemaining,
                    "weekly_limit": settings.extensionWeeklyLimit,
                    "duration_minutes": settings.extensionDurationMinutes
                ],
                "overrides": [
                    "used": overridesUsed,
                    "remaining": overridesRemaining,
                    "weekly_limit": settings.overrideWeeklyLimit,
                    "duration_minutes": settings.overrideDurationMinutes
                ],
                "reset_weekday": settings.resetWeekday.shortName
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
        } else {
            print("Extensions:  \(extensionsRemaining)/\(settings.extensionWeeklyLimit) " +
                "remaining (\(settings.extensionDurationMinutes) min each)")
            print("Overrides:   \(overridesRemaining)/\(settings.overrideWeeklyLimit) " +
                "remaining (\(settings.overrideDurationMinutes) min each)")
            print("Resets:      \(settings.resetWeekday.shortName)")
        }

        // Keep tracker alive to suppress unused warnings — the tracker itself
        // is the production object; we read from ActivityStore for accurate counts.
    }
}
