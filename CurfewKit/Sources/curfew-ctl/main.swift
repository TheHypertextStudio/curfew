import ArgumentParser
import CurfewKit
import Darwin
import Foundation

/// Root command for the Curfew command-line interface.
///
/// `curfew-ctl` reads the same settings and activity log the Curfew app
/// writes, so it shows live state without requiring the app to be running.
/// Extension and schedule change requests use the app's existing approval queue.
/// Protected work and emergency recovery retain their separate bounded
/// stores and never unlock the display.
///
/// Install the bundled command from Curfew Settings or Homebrew.
/// The development package is not the end-user installer.
struct CurfewCLI: ParsableCommand {
    /// ArgumentParser root-command metadata — sub-command list and
    /// default. Defaults to `status` when the binary is invoked with
    /// no arguments so `curfew-ctl` alone prints current state.
    static var configuration = CommandConfiguration(
        commandName: "curfew-ctl",
        abstract: "Inspect or request changes to the current Curfew state (beta).",
        version: "curfew-ctl \(CLIVersion.current)",
        subcommands: [
            StatusCommand.self,
            SetupCommand.self,
            CompletionCommand.self,
            ExplainCommand.self,
            ScheduleCommand.self,
            BudgetCommand.self,
            ActivityCommand.self,
            AuditCommand.self,
            ReflectionCommand.self,
            OverrideCommand.self,
            ExtensionCommand.self,
            RequestCommand.self,
            WorkCommand.self,
            BreakGlassCommand.self
        ],
        defaultSubcommand: StatusCommand.self
    )

    @OptionGroup var options: CLIOptions
}

// Top-level entry point — ArgumentParser's generated main() handles arg parsing.
signal(SIGPIPE, SIG_DFL)
exit(CLIRuntime.run(arguments: Array(CommandLine.arguments.dropFirst()), handlingSignals: true))

// MARK: - Shared helpers

/// Opens the shared settings defaults using the Curfew app's suite name.
/// Returns `.default` settings when the app has never been launched.
func loadSettings() -> CurfewSettings {
    let defaults = UserDefaults(suiteName: SharedPaths.defaultsSuiteName) ?? .standard
    return CurfewSettingsStore(defaults: defaults).load()
}

/// Opens the shared activity SQLite database for inspection.
/// Returns `nil` when the database doesn't exist (app not yet launched).
func openActivityStore(at url: URL = SharedPaths.activityDatabase) throws -> ActivityStore? {
    guard try cliDatabaseExists(at: url) else {
        return nil
    }
    return try ActivityStore(databaseURL: url, readOnly: true)
}

/// Opens the shared reflection SQLite database for inspection.
/// Returns `nil` when the database doesn't exist (no reflections recorded yet).
func openReflectionStore(at url: URL = SharedPaths.reflectionDatabase) throws -> ReflectionStore? {
    guard try cliDatabaseExists(at: url) else {
        return nil
    }
    return try ReflectionStore(databaseURL: url, readOnly: true)
}

private func cliDatabaseExists(at url: URL) throws -> Bool {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else {
        if errno == ENOENT {
            return false
        }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else {
        throw ValidationError("Expected a regular SQLite database at \(url.path).")
    }
    return true
}
