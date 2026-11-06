import ArgumentParser
import Darwin
import Foundation

enum CLIText {
    static func print(
        _ text: String, title: String, options: CLIOptions,
        page: Bool = false, preformatted: Bool = false
    ) throws {
        if options.json {
            Swift.print(text)
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let terminal = isatty(STDOUT_FILENO) == 1
        var size = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        let width = Int(environment["COLUMNS"] ?? "") ?? (size.ws_col > 0 ? Int(size.ws_col) : 80)
        let rows = Int(environment["LINES"] ?? "") ?? (size.ws_row > 0 ? Int(size.ws_row) : 24)
        let result = preformatted ? text : render(
            text, title: title, terminal: terminal, width: width,
            color: colorEnabled(
                terminal: terminal,
                noColor: options.noColor,
                environment: environment
            )
        )
        if page, shouldPage(
            result,
            streams: (stdout: terminal, stdin: isatty(STDIN_FILENO) == 1),
            rows: rows,
            noPager: options.noPager || options.noInput,
            environment: environment
        ) {
            try pageResult(result, environment: environment)
        } else {
            Swift.print(result)
        }
    }

    static func diagnostic(_ text: String) {
        let environment = ProcessInfo.processInfo.environment
        let width = Int(environment["COLUMNS"] ?? "") ?? 80
        let terminal = isatty(STDERR_FILENO) == 1
        let result = render(text, title: "Curfew", terminal: terminal, width: width, color: false)
        FileHandle.standardError.write(Data((result + "\n").utf8))
    }

    static func render(
        _ text: String,
        title: String,
        terminal: Bool,
        width: Int,
        color: Bool
    ) -> String {
        guard terminal else { return text }
        let heading = color ? "\u{1B}[1m\(title)\u{1B}[0m" : title
        let lines = text.components(separatedBy: .newlines).map { line -> String in
            guard !line.isEmpty else { return "" }
            let existing = String(line.prefix(while: { $0 == " " }))
            let margin = "  " + existing
            return wrap(String(line.dropFirst(existing.count)), width: max(1, width - margin.count))
                .map { margin + $0 }.joined(separator: "\n")
        }
        return heading + "\n\n" + lines.joined(separator: "\n")
    }

    static func shouldPage(
        _ text: String,
        streams: (stdout: Bool, stdin: Bool),
        rows: Int,
        noPager: Bool,
        environment: [String: String]
    ) -> Bool {
        let automated = environment["CI"]
            .map { !["false", "0"].contains($0.lowercased()) } ?? false
        return streams.stdout && streams
            .stdin && !noPager && !automated && environment["CURFEW_NO_INPUT"] != "1" &&
            environment["PAGER"] != "" && environment["TERM"] != "dumb" &&
            text.components(separatedBy: .newlines).count > max(1, rows - 1)
    }

    static func colorEnabled(terminal: Bool, noColor: Bool, environment: [String: String]) -> Bool {
        if let value = environment["NO_COLOR"], !value.isEmpty {
            return false
        }
        if noColor {
            return false
        }
        if let value = environment["FORCE_COLOR"], !value.isEmpty, value != "0" {
            return true
        }
        return terminal && environment["TERM"] != "dumb"
    }

    static func wrap(_ text: String, width: Int) -> [String] {
        var result: [String] = []
        var line = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !line.isEmpty, line.count + 1 + word.count > width {
                result.append(line)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word
        }
        if !line.isEmpty {
            result.append(line)
        }
        return result
    }

    private static func pageResult(_ text: String, environment: [String: String]) throws {
        let words = try pagerWords(environment["PAGER"] ?? "/usr/bin/less -FRX")
        guard let command = words.first else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + words.dropFirst()
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do { try process.run() } catch {
            throw CLIError(
                "state.operation_failed",
                "Could not start the configured pager.",
                action: "Check PAGER or use --no-pager.",
                exitStatus: 1
            )
        }
        let previous = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previous) }
        do { try input.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8)) } catch {
            if (error as NSError).code != Int(EPIPE) {
                throw error
            }
        }
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError(
                "state.operation_failed",
                "The configured pager stopped before completing.",
                action: "Check PAGER or use --no-pager.",
                exitStatus: 1
            )
        }
    }

    private static func pagerWords(_ value: String) throws -> [String] {
        var result: [String] = []
        var word = ""
        var quote: Character?
        var escaped = false
        for character in value {
            if escaped {
                word.append(character); escaped = false; continue
            }
            if character == "\\", quote != "'" {
                escaped = true; continue
            }
            if let delimiter = quote {
                if character == delimiter {
                    quote = nil
                } else {
                    word.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !word.isEmpty {
                    result.append(word); word = ""
                }
            } else {
                word.append(character)
            }
        }
        guard quote == nil, !escaped else {
            throw ValidationError("PAGER contains an unfinished quoted argument.")
        }
        if !word.isEmpty {
            result.append(word)
        }
        return result
    }
}
