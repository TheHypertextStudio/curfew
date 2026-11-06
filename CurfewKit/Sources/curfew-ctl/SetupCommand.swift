import ArgumentParser
import CurfewKit
import Foundation

struct SetupCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install the bundled command on PATH. Preview changes unless --apply is given."
    )
    @OptionGroup var options: CLIOptions
    @Flag(name: .long, help: "Install the command and configure the shell PATH.")
    var apply = false
    @Flag(
        name: [.long, .customShort("n")],
        help: "Preview without changing files, even with --apply."
    )
    var dryRun = false
    @Option(
        name: .long,
        help: "Shell to configure: zsh, bash, or fish. Defaults to your login shell."
    )
    var shell: String?

    mutating func validate() throws {
        if let shell,
           !["zsh", "bash", "fish"].contains(URL(fileURLWithPath: shell).lastPathComponent) {
            throw ValidationError("--shell must name zsh, bash, or fish.")
        }
    }

    func run() throws {
        let installer = try CLIInstallation(sourceURL: CLIExecutable.location(), shell: shell)
        let plan = try installer.plan()
        let writes = apply && !dryRun
        if writes {
            try installer.install()
        }
        if options.json {
            var result: [String: Any] = [
                "command": plan.commandURL.path,
                "changes": plan.changes,
                "applied": writes,
                "changed": writes && !plan.changes.isEmpty
            ]
            if let profile = plan.profileURL {
                result["shell_profile"] = profile.path
            }
            try CLIOutput.printJSON(result)
        } else {
            let text: String = if plan.changes.isEmpty {
                "The command is already installed at \(plan.commandURL.path)."
            } else if writes {
                "Curfew installed the command at \(plan.commandURL.path).\n" +
                    "Open a new Terminal and use curfew-ctl --help."
            } else {
                plan.changes.joined(separator: "\n") +
                    "\nUse curfew-ctl setup --apply to install the command."
            }
            try CLIText.print(text, title: "Install curfew-ctl", options: options)
        }
    }
}
