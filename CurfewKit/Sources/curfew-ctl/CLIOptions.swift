import ArgumentParser

struct CLIOptions: ParsableArguments {
    @Flag(name: .customShort("V"), help: "Print the CLI version.")
    var version: Bool = false

    @Flag(name: [.long, .customShort("j")], help: "Print one versioned JSON result.")
    var json: Bool = false

    @Flag(name: .shortAndLong, help: "Print operation details to stderr.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Include diagnostic details on stderr. Implies --verbose.")
    var debug: Bool = false

    @Flag(name: .shortAndLong, help: "Print results, warnings, and errors only.")
    var quiet: Bool = false

    @Flag(name: .long, help: "Print without terminal color.")
    var noColor: Bool = false

    @Flag(name: .long, help: "Never ask for terminal input.")
    var noInput: Bool = false

    @Flag(name: .long, help: "Print long results directly without a pager.")
    var noPager: Bool = false

    mutating func validate() throws {
        if version {
            throw CleanExit.message("curfew-ctl \(CLIVersion.current)")
        }
        guard !quiet || (!verbose && !debug) else {
            throw ValidationError("--quiet cannot be combined with --verbose or --debug.")
        }
    }
}
