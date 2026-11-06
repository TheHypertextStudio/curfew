import ArgumentParser
import Foundation

struct CompletionCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Print shell completion for bash, zsh, or fish."
    )

    @Argument(help: "Shell: bash, zsh, or fish.")
    var shell: String

    @OptionGroup var options: CLIOptions

    func run() throws {
        let script = try Self.script(for: shell)
        if options.json {
            try CLIOutput.printJSON(["shell": shell, "script": script])
        } else {
            print(script)
        }
    }

    static func script(for name: String) throws -> String {
        let shell: CompletionShell
        switch name {
        case "bash": shell = .bash
        case "zsh": shell = .zsh
        case "fish": shell = .fish
        default: throw ValidationError("Completion supports bash, zsh, and fish.")
        }
        return CurfewCLI.completionScript(for: shell)
    }
}
