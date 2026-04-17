import ArgumentParser
import CurfewKit
import Foundation

/// Root command for the Curfew command-line interface.
///
/// `curfew-ctl` reads the same settings and activity log the Curfew app
/// writes, so it shows live state without requiring the app to be running.
/// Mutating subcommands never change enforcement directly; they enqueue a
/// request onto the same queue the MCP server uses, so the running app
/// raises a consent sheet and the action passes through the
/// `AIConsentPolicy` gate.
///
/// Install: copy the `curfew-ctl` binary to `/usr/local/bin/` after
/// building with `swift build -c release`.
struct CurfewCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "curfew-ctl",
        abstract: "Inspect or request changes to the current Curfew state.",
        subcommands: [
            StatusCommand.self,
            ScheduleCommand.self,
            BudgetCommand.self,
            ActivityCommand.self,
            OverrideCommand.self
        ],
        defaultSubcommand: StatusCommand.self
    )
}

// Top-level entry point — ArgumentParser's generated main() handles arg parsing.
CurfewCLI.main()

// MARK: - Shared helpers

/// Opens the shared settings defaults using the Curfew app's suite name.
/// Returns `.default` settings when the app has never been launched.
func loadSettings() -> CurfewSettings {
    let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    return CurfewSettingsStore(defaults: defaults).load()
}

/// Opens the shared activity SQLite database read-only.
/// Returns `nil` when the database doesn't exist (app not yet launched).
func openActivityStore() -> ActivityStore? {
    guard FileManager.default.fileExists(
        atPath: SharedPaths.activityDatabase.path
    ) else {
        return nil
    }
    return try? ActivityStore(databaseURL: SharedPaths.activityDatabase)
}
