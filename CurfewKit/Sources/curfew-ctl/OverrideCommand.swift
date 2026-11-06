import ArgumentParser

/// Retains the legacy invocation so callers receive the required recovery path.
struct OverrideCommand: ParsableCommand {
    static let message = """
    Overrides require confirmation in Curfew. Use ‘Need to get back in?’ on the lockout screen. \
    For emergency shutdown recovery, see curfew-ctl break-glass --help.
    """

    static var configuration = CommandConfiguration(
        commandName: "override",
        abstract: "Show how to request an override in the Curfew app."
    )

    @Argument(help: "Legacy override reason.")
    var reason: String?

    @Option(name: .customLong("reason"), help: "Legacy override reason. Overrides require the app.")
    var legacyReason: String?

    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    mutating func validate() throws {
        throw ValidationError(Self.message)
    }

    func run() throws {
        throw ValidationError(Self.message)
    }
}
