import ArgumentParser
import CurfewKit
import Foundation

/// Reads the persisted budget authority used to grant extensions and overrides.
struct BudgetCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "budget",
        abstract: "Show extension and override budget remaining this week."
    )

    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    func run() throws {
        let settings = loadSettings()
        let trackers = try Self.trackers(
            settings: settings,
            store: .production(),
            now: Date(),
            calendar: .current
        )
        if json {
            let object = try Self.jsonObject(
                settings: settings,
                extensions: trackers.extensions,
                overrides: trackers.overrides
            )
            let data = try CLIOutput.data(object)
            guard let output = String(bytes: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            print(output)
        } else {
            let lines = [
                "Extensions: \(trackers.extensions.remaining)/\(settings.extensionWeeklyLimit) remaining (\(settings.extensionDurationMinutes) min each)",
                "Overrides: \(trackers.overrides.remaining)/\(settings.overrideWeeklyLimit) remaining (\(settings.overrideDurationMinutes) min each)",
                "Resets: \(settings.resetWeekday.shortName)"
            ]
            try CLIText.print(
                lines.joined(separator: "\n"),
                title: "Weekly budgets",
                options: options
            )
        }
    }

    static func snapshot(
        settings: CurfewSettings,
        store: EnforcementRuntimeStateStore,
        now: Date,
        calendar: Calendar
    ) throws -> [String: Any] {
        let trackers = try trackers(settings: settings, store: store, now: now, calendar: calendar)
        return try jsonObject(
            settings: settings,
            extensions: trackers.extensions,
            overrides: trackers.overrides
        )
    }

    private static func trackers(
        settings: CurfewSettings,
        store: EnforcementRuntimeStateStore,
        now: Date,
        calendar: Calendar
    ) throws -> (extensions: ExtensionBudgetTracker, overrides: ExtensionBudgetTracker) {
        guard let state = try store.load() else {
            throw CLIError(
                "state.unavailable",
                "No grant history is available. " +
                    "Open Curfew and complete setup before reading budgets.",
                exitStatus: 69
            )
        }
        let extensions = ExtensionBudgetTracker(
            weeklyLimit: settings.extensionWeeklyLimit,
            extensionMinutes: settings.extensionDurationMinutes,
            resetWeekday: settings.resetWeekday,
            calendar: calendar,
            seedLastResetBoundary: state.extensionResetBoundary,
            seedUsedCount: state.extensionUses
        )
        let overrides = ExtensionBudgetTracker(
            weeklyLimit: settings.overrideWeeklyLimit,
            extensionMinutes: settings.overrideDurationMinutes,
            resetWeekday: settings.resetWeekday,
            calendar: calendar,
            seedLastResetBoundary: state.overrideResetBoundary,
            seedUsedCount: state.overrideUses
        )
        extensions.resetIfNeeded(at: now)
        overrides.resetIfNeeded(at: now)
        return (extensions, overrides)
    }

    private static func jsonObject(
        settings: CurfewSettings,
        extensions: ExtensionBudgetTracker,
        overrides: ExtensionBudgetTracker
    ) throws -> [String: Any] {
        try [
            "extensions": [
                "used": extensions.usedCount,
                "remaining": extensions.remaining,
                "weekly_limit": extensions.weeklyLimit,
                "duration_seconds": CLIOutput.durationSeconds(extensions.extensionMinutes)
            ],
            "overrides": [
                "used": overrides.usedCount,
                "remaining": overrides.remaining,
                "weekly_limit": overrides.weeklyLimit,
                "duration_seconds": CLIOutput.durationSeconds(overrides.extensionMinutes)
            ],
            "reset_weekday": settings.resetWeekday.shortName
        ]
    }
}
