import ArgumentParser
import CurfewKit
import Foundation

struct ScheduleSetCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Request a change to a time-based weekday rule (beta).",
        discussion: "Curfew applies its approval policy and schedule cooldowns to this request."
    )

    @Argument(help: "Weekday, such as monday.") var weekday: String
    @Option(name: .customLong("lock"), help: "Lock time in 24-hour HH:MM.") var lockTime: String
    @Option(
        name: .customLong("unlock"),
        help: "Unlock time in 24-hour HH:MM."
    ) var unlockTime: String?
    @Option(
        name: .customLong("day-off"),
        help: "Set the day off to true or false."
    ) var dayOff: Bool?
    @Option(help: "Stable UUID for safely retrying this same request.") var id: String?
    @Flag(
        name: [.long, .customShort("n")],
        help: "Preview the request without signing or queuing it."
    )
    var dryRun = false
    @OptionGroup var options: CLIOptions

    mutating func validate() throws {
        guard selectedWeekday != nil else {
            throw ValidationError("Enter a full weekday name, such as monday.")
        }
        guard Self.validTime(lockTime), unlockTime.map(Self.validTime) ?? true else {
            throw ValidationError("Enter a 24-hour time in HH:MM, such as 22:00.")
        }
        _ = try id.map(parseCLIRequestID)
    }

    func run() throws {
        let settings = try CurfewSettingsStore.production().loadChecked()
        try submitCLIRequest(
            makeRequest(settings: settings), json: options.json, dryRun: dryRun,
            options: options, settings: settings
        )
    }

    func makeRequest(settings: CurfewSettings) throws -> MCPPendingRequest {
        guard let selectedWeekday else {
            throw ValidationError("Enter a full weekday name, such as monday.")
        }
        guard settings.schedule.rule(for: selectedWeekday).mode == .time else {
            throw CLIError(
                "state.unavailable",
                "Use Curfew Settings to edit rules that include an hours limit.",
                exitStatus: 69
            )
        }

        var arguments = ["weekday": weekday.lowercased(), "lock_time": lockTime]
        arguments["unlock_time"] = unlockTime
        arguments["is_day_off"] = dayOff.map(String.init)
        let data = try JSONSerialization.data(withJSONObject: arguments, options: .sortedKeys)
        guard let payload = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return try MCPPendingRequest(
            id: id.map(parseCLIRequestID) ?? UUID(), tool: .setSchedule, argumentsJSON: payload
        )
    }

    private var selectedWeekday: Weekday? {
        Weekday.allCases.first { String(describing: $0) == weekday.lowercased() }
    }

    private static func validTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ part in
                  part.utf8.count == 2 && part.utf8.allSatisfy { (48 ... 57).contains($0) }
              }),
              let hour = Int(parts[0]), let minute = Int(parts[1]) else { return false }
        return hour < 24 && minute < 60
    }
}
