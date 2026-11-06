import ArgumentParser
import CurfewKit
import Darwin
import Foundation

struct AuditCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Read retained activity from the app or privileged daemon audit log."
    )
    @Option(name: .long, help: "Audit stream: app or daemon. Daemon logs may require sudo.")
    var stream: String = "app"
    @Option(name: .long, help: "Number of days to include, counting today. Defaults to 7.")
    var days: Int?
    @Option(name: .long, help: "Include events since this ISO 8601 timestamp.")
    var since: String?
    @Option(name: .long, help: "Maximum number of recent records. Defaults to 1000.")
    var limit: Int = 1000
    @OptionGroup var options: CLIOptions
    var json: Bool {
        options.json
    }

    mutating func validate() throws {
        guard AuditStream(rawValue: stream) != nil
        else { throw ValidationError("--stream must be app or daemon.") }
        if let days, days < 1 {
            throw ValidationError("--days must be at least 1.")
        }
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
        guard days == nil || since == nil
        else { throw ValidationError("Use either --days or --since.") }
        if let since,
           Self
               .date(since) ==
               nil {
            throw ValidationError("--since must be an ISO 8601 timestamp with a timezone.")
        }
    }

    func run() throws {
        guard let selected = AuditStream(rawValue: stream)
        else { throw ValidationError("Unknown audit stream.") }
        let now = Date()
        let start: Date = if let since, let parsed = Self.date(since) {
            parsed
        } else {
            Calendar.current.date(
                byAdding: .day,
                value: -((days ?? 7) - 1),
                to: Calendar.current.startOfDay(for: now)
            ) ?? now
        }
        let records = try Self.records(
            directory: AuditLogPaths.directory(for: selected),
            stem: AuditLogPaths.baseName(for: selected),
            since: start
        )
        let recent = Array(records.suffix(limit))
        if json {
            let object: [String: Any] = [
                "stream": stream,
                "records": recent,
                "truncated": records.count > limit
            ]
            try CLIOutput.printJSON(object)
        } else {
            let separator = isatty(STDOUT_FILENO) == 1 ? "  " : "\t"
            let rows = recent.map { record in
                ["ts", "event", "actor"].map { key in
                    String(describing: record[key] ?? "")
                        .replacingOccurrences(of: "\t", with: " ")
                        .replacingOccurrences(of: "\n", with: " ")
                }.joined(separator: separator)
            }
            let text = records.isEmpty ? "No audit events in the requested range." : rows
                .joined(separator: "\n")
            try CLIText.print(text, title: "Audit events", options: options, page: true)
            if records.count > limit {
                let message = "Showing the most recent \(limit) records. Increase --limit to include more.\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
        }
    }

    static func records(directory: URL, stem: String, since: Date) throws -> [[String: Any]] {
        var result: [(Date, [String: Any])] = []
        for segment in stride(
            from: AuditRotationPolicy.standard.maxRotatedSegments,
            through: 0,
            by: -1
        ) {
            let name = segment == 0 ? "\(stem).jsonl" : "\(stem).\(segment).jsonl"
            let url = directory.appendingPathComponent(name)
            guard let data = try BoundedRegularFileReader.read(url, maximumBytes: 16 * 1024 * 1024)
            else { continue }
            guard let text = String(data: data, encoding: .utf8)
            else { throw CLIError(
                "data.invalid_state",
                "Audit file is not UTF-8: \(url.path)",
                exitStatus: 65
            ) }
            for (lineNumber, line) in text.split(separator: "\n").enumerated() {
                guard let object = (try? JSONSerialization
                    .jsonObject(with: Data(line.utf8))) as? [String: Any],
                    let timestamp = object["ts"] as? String, let date = date(timestamp),
                    object["event"] is String else {
                    throw CLIError(
                        "data.invalid_state",
                        "Invalid audit record at \(url.path):\(lineNumber + 1).",
                        exitStatus: 65
                    )
                }
                if date >= since {
                    result.append((date, object))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}
