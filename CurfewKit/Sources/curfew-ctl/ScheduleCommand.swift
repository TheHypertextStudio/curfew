import ArgumentParser
import CurfewKit
import Foundation

struct ScheduleCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "schedule",
        abstract: "Inspect saved weekly rules or request a schedule change.",
        subcommands: [ScheduleShowCommand.self, ScheduleSetCommand.self],
        defaultSubcommand: ScheduleShowCommand.self
    )

    @OptionGroup var options: CLIOptions

    static func jsonData(settings: CurfewSettings, automaticScheduleEnabled: Bool) throws -> Data {
        var object: [String: Any] = try [
            "automatic_schedule_enabled": automaticScheduleEnabled,
            "days": days(settings.schedule)
        ]
        if let pending = settings.pendingScheduleChange {
            let iso = ISO8601DateFormatter()
            object["pending_change"] = try [
                "requested_at": iso.string(from: pending.requestedAt),
                "effective_at": iso.string(from: pending.effectiveAt),
                "classification": pending.classification.rawValue,
                "days": days(pending.proposedSchedule)
            ] as [String: Any]
        }
        return try CLIOutput.data(object)
    }

    private static func days(_ schedule: WeeklySchedule) throws -> [[String: Any]] {
        try Weekday.allCases.map { weekday in
            let rule = schedule.rule(for: weekday)
            var day: [String: Any] = [
                "day": weekday.shortName, "day_off": rule.isDayOff,
                "mode": rule.mode.rawValue,
                "lock": minutesToHHMM(rule.lockMinutes),
                "unlock": minutesToHHMM(rule.unlockMinutes)
            ]
            if let minutes = rule.hoursLimitMinutes {
                day["hours_limit_seconds"] = try CLIOutput.durationSeconds(minutes)
            }
            return day
        }
    }
}

struct ScheduleShowCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show saved weekly rules and whether automatic scheduling is enabled."
    )

    @OptionGroup var options: CLIOptions

    func run() throws {
        let store = CurfewSettingsStore.production()
        let settings = try store.loadChecked()
        let enabled = AutomaticScheduleConsentPolicy.isEnabled(
            savedConsent: store.loadAutomaticScheduleConsent(),
            hasCompletedInitialSetup: settings.hasCompletedInitialSetup,
            flavor: .current
        )
        if options.json {
            try print(String(
                data: ScheduleCommand.jsonData(
                    settings: settings,
                    automaticScheduleEnabled: enabled
                ),
                encoding: .utf8
            ) ?? "{}")
        } else {
            var lines = [
                "Automatic weekly schedule: \(enabled ? "on" : "off")",
                "Saved weekly rules\(enabled ? "" : " (inactive)"):",
                settings.schedule.reviewLines.joined(separator: "\n")
            ]
            if let pending = settings.pendingScheduleChange {
                lines
                    .append(
                        "Pending change effective: \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                lines.append(pending.proposedSchedule.reviewLines.joined(separator: "\n"))
            }
            try CLIText.print(
                lines.joined(separator: "\n"),
                title: "Weekly schedule",
                options: options
            )
        }
    }
}
