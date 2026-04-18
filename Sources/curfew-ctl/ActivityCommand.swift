import ArgumentParser
import CurfewKit
import Foundation

/// Prints recent activity events from the local log.
struct ActivityCommand: ParsableCommand {
    /// ArgumentParser command metadata — name, short abstract, and
    /// usage. Read by the parent `curfew-ctl` to build its help output.
    static var configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "Show recent activity events from the local log."
    )

    /// Narrow the output to events from today only.
    @Flag(name: .long, help: "Show only today's events.")
    var today: Bool = false

    /// Emit JSON rather than the default human-readable format.
    @Flag(name: .shortAndLong, help: "Output as JSON instead of plain text.")
    var json: Bool = false

    /// Entry point — opens the activity store, filters to the requested
    /// window, and prints each event.
    func run() {
        guard let store = openActivityStore() else {
            print("No activity log found. Has Curfew been launched yet?")
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let rangeStart: Date = if today {
            calendar.startOfDay(for: now)
        } else {
            // Week view: events since Monday of the current week.
            calendar.startOfWeek(for: now)
        }

        let events: [ActivityEvent]
        do {
            events = try store.events(in: rangeStart ... now)
        } catch {
            fputs("Error reading activity log: \(error)\n", stderr)
            return
        }

        if events.isEmpty {
            print(today ? "No events today." : "No events this week.")
            return
        }

        if json {
            printJSON(events: events)
        } else {
            printPlain(events: events)
        }
    }

    // MARK: - Output formatters

    private func printPlain(events: [ActivityEvent]) {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        for event in events.reversed() {
            let time = formatter.string(from: event.timestamp)
            let label = eventLabel(event)
            print("  \(time)  \(label)")
        }
    }

    private func printJSON(events: [ActivityEvent]) {
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = events.map { event in
            var obj: [String: Any] = [
                "timestamp": iso.string(from: event.timestamp),
                "kind": event.kind.rawValue,
                "gate_kind": event.gateKind
            ]
            if let minutes = event.minutesValue {
                obj["minutes"] = minutes
            }
            if let note = event.note {
                obj["note"] = note
            }
            return obj
        }
        if let data = try? JSONSerialization.data(
            withJSONObject: ["events": items],
            options: [.prettyPrinted, .sortedKeys]
        ) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
    }

    // MARK: - Helpers

    private func eventLabel(_ event: ActivityEvent) -> String {
        switch event.kind {
        case .sessionStarted:
            return "Session started"
        case .sessionEnded:
            return "Session ended"
        case .warningEscalated:
            let stage = event.note ?? "T-?"
            let mins = event.minutesValue.map { "\($0) min" } ?? ""
            return "Warning: \(stage) (\(mins) remaining)"
        case .lockoutStarted:
            return "Lockout started"
        case .lockoutEnded:
            return "Lockout ended"
        case .extensionGranted:
            let mins = event.minutesValue.map { "+\($0) min" } ?? ""
            return "Extension granted \(mins)"
        case .overrideGranted:
            let mins = event.minutesValue.map { "+\($0) min" } ?? ""
            let reason = event.note.map { " — \($0)" } ?? ""
            return "Override granted \(mins)\(reason)"
        case .dayOff:
            return "Day off"
        }
    }
}
