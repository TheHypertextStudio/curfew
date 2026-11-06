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

    @Option(name: .long, help: "Number of days to include, counting today.")
    var days: Int?

    mutating func validate() throws {
        if let days, days < 1 {
            throw ValidationError("--days must be at least 1.")
        }
        if today, days != nil {
            throw ValidationError("Use either --today or --days.")
        }
    }

    /// Emit JSON rather than the default human-readable format.
    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    /// Entry point — opens the activity store, filters to the requested
    /// window, and prints each event.
    func run() throws {
        guard let store = try openActivityStore() else {
            if json {
                try print(String(data: Self.jsonData(events: []), encoding: .utf8) ?? "{}")
                return
            }
            try CLIText.print(
                "No activity log is available. Open Curfew to start recording activity.",
                title: "Activity",
                options: options
            )
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let rangeStart: Date = if today {
            calendar.startOfDay(for: now)
        } else if let days {
            calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))
                ?? calendar.startOfDay(for: now)
        } else {
            // Week view: events since Monday of the current week.
            calendar.startOfWeek(for: now)
        }

        let events = try store.events(in: rangeStart ... now)
        if json {
            try print(String(data: Self.jsonData(events: events), encoding: .utf8) ?? "{}")
        } else if events.isEmpty {
            try CLIText.print(
                "No events in the requested range.",
                title: "Activity",
                options: options
            )
        } else {
            try printPlain(events: events)
        }
    }

    // MARK: - Output formatters

    private func printPlain(events: [ActivityEvent]) throws {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let lines = events.reversed().map { event in
            let time = formatter.string(from: event.timestamp)
            let label = eventLabel(event)
            return "\(time)  \(label)"
        }
        try CLIText.print(
            lines.joined(separator: "\n"),
            title: "Activity",
            options: options,
            page: true
        )
    }

    static func jsonData(events: [ActivityEvent]) throws -> Data {
        let iso = ISO8601DateFormatter()
        let items: [[String: Any]] = try events.map { event in
            var obj: [String: Any] = [
                "timestamp": iso.string(from: event.timestamp),
                "kind": event.kind.rawValue,
                "gate_kind": event.gateKind
            ]
            if let minutes = event.minutesValue {
                obj["seconds"] = try CLIOutput.durationSeconds(minutes)
            }
            if let note = event.note {
                obj["note"] = note
            }
            return obj
        }
        return try CLIOutput.data(["events": items])
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
        case .reflectionRecorded:
            return "Reflection recorded (\(event.gateKind))"
        }
    }
}
