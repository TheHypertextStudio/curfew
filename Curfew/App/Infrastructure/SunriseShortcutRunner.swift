import CurfewKit
import Foundation

/// What one call to the `shortcuts` command returned.
nonisolated struct SunriseShortcutLaunchResult: Sendable {
    let status: Int32
    let output: String
}

/// Starts the system `shortcuts` command. Injected so tests never list or run
/// a real Shortcut.
nonisolated protocol SunriseShortcutLaunching: Sendable {
    func run(arguments: [String]) async -> SunriseShortcutLaunchResult
}

/// Lists and runs the person's Shortcuts through `/usr/bin/shortcuts`, the
/// system's supported command for both. Running never blocks Sunrise's
/// release: callers start it after the gate has closed and only read the
/// result.
nonisolated struct SunriseShortcutRunner: Sendable {
    let launcher: any SunriseShortcutLaunching
    var temporaryDirectory: URL = FileManager.default.temporaryDirectory

    /// The runner the app uses. Inert in the unit-test host, so no test can
    /// reach the real command.
    static var live: SunriseShortcutRunner {
        SunriseShortcutRunner(
            launcher: RuntimeEnvironment.isUnitTestHost
                ? InertShortcutLauncher() as any SunriseShortcutLaunching
                : ProcessShortcutLauncher()
        )
    }

    var isInert: Bool {
        launcher is InertShortcutLauncher
    }

    /// The person's shortcuts, by name, from `shortcuts list --show-identifiers`
    /// (one "Name (identifier)" per line). Empty when listing fails.
    func list() async -> [SunriseShortcut] {
        let result = await launcher.run(arguments: ["list", "--show-identifiers"])
        guard result.status == 0 else { return [] }
        return result.output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasSuffix(")"), let open = text.range(of: " (", options: .backwards)
            else { return nil }
            let name = String(text[..<open.lowerBound])
            let identifier = String(text[open.upperBound ..< text.index(before: text.endIndex)])
            guard !name.isEmpty, UUID(uuidString: identifier) != nil else { return nil }
            return SunriseShortcut(identifier: identifier, name: name)
        }
    }

    /// Runs `shortcut` with `input` as its text input. Returns whether it ran.
    func run(_ shortcut: SunriseShortcut, input: String) async -> Bool {
        let file = temporaryDirectory
            .appendingPathComponent("curfew-sunrise-\(UUID().uuidString).txt")
        do {
            try Data(input.utf8).write(to: file, options: [.atomic])
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await launcher.run(
            arguments: ["run", shortcut.identifier, "--input-path", file.path]
        )
        return result.status == 0
    }
}

/// Never runs anything. Used in the unit-test host and demo sessions.
nonisolated struct InertShortcutLauncher: SunriseShortcutLaunching {
    func run(arguments _: [String]) async -> SunriseShortcutLaunchResult {
        SunriseShortcutLaunchResult(status: 1, output: "")
    }
}

/// Starts `/usr/bin/shortcuts` as a child process and waits for it to exit.
nonisolated struct ProcessShortcutLauncher: SunriseShortcutLaunching {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    func run(arguments: [String]) async -> SunriseShortcutLaunchResult {
        // Off the main actor: reading to the end of output before waiting
        // keeps a long listing from filling the pipe and stalling the child.
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = Self.executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return SunriseShortcutLaunchResult(status: -1, output: "")
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return SunriseShortcutLaunchResult(
                status: process.terminationStatus,
                output: String(bytes: data, encoding: .utf8) ?? ""
            )
        }.value
    }
}
