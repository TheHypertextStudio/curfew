import ArgumentParser
import Darwin
import Foundation

enum CLIRuntime {
    static func run(
        arguments: [String],
        handlingSignals: Bool = false,
        output: @escaping (String) -> Void = { print($0) },
        diagnostic: @escaping (String) -> Void = CLIText.diagnostic
    ) -> Int32 {
        let context = Context(
            arguments: arguments,
            handlingSignals: handlingSignals,
            output: output,
            diagnostic: diagnostic
        )
        let interrupts = handlingSignals
            ? CLIInterrupts(message: diagnostic, forceExit: { _exit($0) }) : nil
        interrupts?.start()
        defer { interrupts?.stop() }
        var parsing = true
        do {
            try CLIArguments.validate(arguments)
            var command = try CurfewCLI.parseAsRoot(arguments)
            parsing = false
            if context.verbose {
                diagnostic("Curfew CLI \(CLIVersion.current): \(type(of: command)._commandName).")
            }
            try command.run()
            return finish(0, interrupts: interrupts, diagnostic: diagnostic)
        } catch {
            let status = CurfewCLI.exitCode(for: error).isSuccess
                ? context.cleanExit(error) : context.failure(error, parsing: parsing)
            return finish(status, interrupts: interrupts, diagnostic: diagnostic)
        }
    }

    private static func finish(
        _ status: Int32,
        interrupts: CLIInterrupts?,
        diagnostic: (String) -> Void
    ) -> Int32 {
        guard let interrupted = interrupts?.exitStatus else { return status }
        diagnostic("Stopped. Completed changes were kept.")
        return interrupted
    }

    private struct Context {
        let arguments: [String]
        let handlingSignals: Bool
        let output: (String) -> Void
        let diagnostic: (String) -> Void

        var flags: [String] {
            Array(arguments.prefix(while: { $0 != "--" }))
        }

        var json: Bool {
            hasFlag("--json", short: "j")
        }

        var debug: Bool {
            flags.contains("--debug")
        }

        var verbose: Bool {
            debug || hasFlag("--verbose", short: "v")
        }

        private func hasFlag(_ name: String, short: Character) -> Bool {
            flags.contains { flag in
                if flag == name {
                    return true
                }
                guard flag.hasPrefix("-"), !flag.hasPrefix("--") else { return false }
                let letters = flag.dropFirst()
                return letters.contains(short) && letters.allSatisfy { "jvqVnh".contains($0) }
            }
        }

        func cleanExit(_ error: any Error) -> Int32 {
            let raw = CurfewCLI.fullMessage(for: error)
            let isHelp = raw.contains("USAGE:")
            let text = isHelp ? CLIHelp.render(raw) : raw
            if json {
                let key = isHelp ? "help" : "version"
                if let data = try? CLIOutput.data([key: text.trimmingCharacters(in: .newlines)]),
                   let result = String(bytes: data, encoding: .utf8) {
                    output(result)
                }
            } else if handlingSignals {
                do {
                    var options = try CLIOptions.parse([])
                    options.noPager = flags.contains("--no-pager")
                    options.noInput = flags.contains("--no-input")
                    try CLIText.print(
                        text,
                        title: "Help",
                        options: options,
                        page: isHelp,
                        preformatted: true
                    )
                } catch { return failure(error, parsing: false) }
            } else {
                output(text)
            }
            return 0
        }

        func failure(_ error: any Error, parsing: Bool) -> Int32 {
            let failure = CLIError.classify(error, parsing: parsing)
            diagnostic(failure.text)
            if failure.exitStatus == 70, let url = Self.supportFile(for: error) {
                diagnostic("Details: \(url.path)")
            }
            if debug {
                diagnostic("Diagnostic: \(String(reflecting: error))")
            }
            if json, let data = try? CLIOutput.data(
                ["error": failure.object],
                status: [69, 77].contains(failure.exitStatus) ? "blocked" : "error"
            ), let result = String(bytes: data, encoding: .utf8) {
                output(result)
            }
            return failure.exitStatus
        }

        private static func supportFile(for error: any Error) -> URL? {
            let manager = FileManager.default
            let environment = ProcessInfo.processInfo.environment
            let base = environment["XDG_STATE_HOME"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("Curfew/logs")
            } ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Curfew")
            let directory = base.appendingPathComponent("CLI", isDirectory: true)
            let url = directory.appendingPathComponent("failure-\(UUID().uuidString).log")
            do {
                try manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                guard manager.createFile(
                    atPath: url.path,
                    contents: Data(String(reflecting: error).utf8),
                    attributes: [.posixPermissions: 0o600]
                ) else { return nil }
                return url
            } catch { return nil }
        }
    }
}

enum CLIArguments {
    static func validate(_ arguments: [String]) throws {
        let scalar: Set = [
            "--days",
            "--gate",
            "--stream",
            "--since",
            "--before",
            "--limit",
            "--reason",
            "--id",
            "--lock",
            "--unlock",
            "--day-off",
            "--label",
            "--minutes",
            "--shell"
        ]
        let aliases = ["-r": "--reason", "-l": "--label", "-m": "--minutes"]
        var seen: Set<String> = []
        var skipValue = false
        for argument in arguments {
            if skipValue {
                skipValue = false; continue
            }
            if argument == "--" {
                break
            }
            let name = String(argument.prefix { $0 != "=" })
            let canonical = aliases[name] ?? name
            if scalar.contains(canonical) {
                guard seen.insert(canonical).inserted else {
                    throw ValidationError("\(canonical) can be given only once.")
                }
                skipValue = !argument.contains("=")
            }
        }
    }
}
