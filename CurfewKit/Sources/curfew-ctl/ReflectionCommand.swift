import ArgumentParser
import CurfewKit
import Foundation

/// Prints recorded reflections (morning intent / evening retrospective) from
/// the local log. Read-only — reflections are authored in the app.
struct ReflectionCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "reflections",
        abstract: "Show recorded morning and evening reflections."
    )

    /// How many days back to include (counting from the start of that day).
    @Option(name: .long, help: "Number of days back to include (default 7).")
    var days: Int = 7

    /// Restrict output to a single gate.
    @Option(name: .long, help: "Filter by gate: morning or evening.")
    var gate: String?

    /// Emit JSON rather than the default human-readable format.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    func run() throws {
        let gateFilter: ReflectionGate?
        if let gate {
            guard let parsed = ReflectionGate(rawValue: gate.lowercased()) else {
                throw ValidationError("gate must be \"morning\" or \"evening\".")
            }
            gateFilter = parsed
        } else {
            gateFilter = nil
        }

        guard let store = openReflectionStore() else {
            print("No reflections found. Has Curfew been launched yet?")
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let rangeStart = calendar.date(byAdding: .day, value: -max(0, days - 1), to: dayStart)
            ?? dayStart

        let reflections: [Reflection]
        do {
            reflections = try store.reflections(in: rangeStart ... now)
                .filter { gateFilter == nil || $0.gate == gateFilter }
        } catch {
            fputs("Error reading reflections: \(error)\n", stderr)
            return
        }

        if reflections.isEmpty {
            print("No reflections in the last \(days) day\(days == 1 ? "" : "s").")
            return
        }

        if json {
            printJSON(reflections: reflections)
        } else {
            printPlain(reflections: reflections)
        }
    }

    // MARK: - Output formatters

    private func printPlain(reflections: [Reflection]) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        for reflection in reflections.reversed() {
            let when = formatter.string(from: reflection.timestamp)
            let gateLabel = reflection.gate == .morning ? "Morning" : "Evening"
            print("\(when) — \(gateLabel)")
            for answer in reflection.answers {
                print("  • \(answer.promptTextSnapshot)")
                print("      \(valueText(answer.value))")
            }
        }
    }

    private func printJSON(reflections: [Reflection]) {
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = reflections.map { reflection in
            [
                "timestamp": iso.string(from: reflection.timestamp),
                "gate": reflection.gate.rawValue,
                "answers": reflection.answers.map(reflectionAnswerJSON)
            ]
        }
        if let data = try? JSONSerialization.data(
            withJSONObject: ["reflections": items],
            options: [.prettyPrinted, .sortedKeys]
        ) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    private func valueText(_ value: ReflectionValue) -> String {
        reflectionValueText(value)
    }
}
