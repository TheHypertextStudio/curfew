import ArgumentParser
@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct ScheduleCommandTests {
    @Test("Schedule editing remains available and visibly beta")
    func scheduleEditingIsBeta() throws {
        let command = try CurfewCLI.parseAsRoot([
            "schedule", "set", "monday", "--lock", "22:00", "--dry-run"
        ])
        #expect(type(of: command).configuration.commandName == "set")
        #expect(type(of: command).configuration.abstract.contains("beta"))
    }

    @Test("Schedule editing uses the existing request payload and preserves the retry ID")
    func scheduleRequest() throws {
        let id = UUID()
        let command = try #require(CurfewCLI.parseAsRoot([
            "schedule", "set", "Monday", "--lock", "22:00", "--unlock", "07:00",
            "--day-off", "false", "--id", id.uuidString
        ]) as? ScheduleSetCommand)
        let request = try command.makeRequest(settings: .default)
        #expect(request.id == id)
        #expect(request.tool == .setSchedule)
        let args = try JSONSerialization.jsonObject(with: Data(request.argumentsJSON.utf8))
            as? [String: String]
        #expect(args == [
            "weekday": "monday",
            "lock_time": "22:00",
            "unlock_time": "07:00",
            "is_day_off": "false"
        ])
    }

    @Test("Schedule editing rejects unsupported input and protects hours rules")
    func scheduleInput() throws {
        for (day, time) in [
            ("mon", "22:00"),
            ("monday", "24:00"),
            ("monday", "9:30"),
            ("monday", "21:60")
        ] {
            #expect(throws: (any Error).self) {
                _ = try CurfewCLI.parseAsRoot(["schedule", "set", day, "--lock", time])
            }
        }
        let command = try #require(CurfewCLI.parseAsRoot([
            "schedule", "set", "monday", "--lock", "22:00"
        ]) as? ScheduleSetCommand)
        var settings = CurfewSettings.default
        settings.schedule = WeeklySchedule(rules: [.monday: DayRule(
            isDayOff: false, lockMinutes: 1080, unlockMinutes: 480, mode: .hours,
            hoursLimitMinutes: 240
        )])
        #expect(throws: CLIError.self) { _ = try command.makeRequest(settings: settings) }
    }

    @Test("Default and explicit schedule inspection use the same command")
    func scheduleInspectionRoutes() throws {
        for arguments in [["schedule"], ["schedule", "show", "--json"]] {
            let command = try CurfewCLI.parseAsRoot(arguments)
            #expect(type(of: command).configuration.commandName == "show")
        }
    }

    @Test("Schedule JSON identifies inactive saved rules and hours triggers")
    func inactiveSchedule() throws {
        var settings = CurfewSettings.default
        settings.schedule = WeeklySchedule(rules: [.monday: DayRule(
            isDayOff: false,
            lockMinutes: 1080,
            unlockMinutes: 480,
            mode: .hours,
            hoursLimitMinutes: 240
        )])
        let object = try JSONSerialization.jsonObject(with: ScheduleCommand.jsonData(
            settings: settings,
            automaticScheduleEnabled: false
        )) as? [String: Any]
        #expect(object?["automatic_schedule_enabled"] as? Bool == false)
        let days = try #require(object?["days"] as? [[String: Any]])
        let monday = try #require(days.first { $0["day"] as? String == "Mon" })
        #expect(monday["mode"] as? String == "hours")
        #expect(monday["hours_limit_seconds"] as? Int == 14400)
        #expect(monday["hours_limit_minutes"] == nil)
    }

    @Test("Schedule JSON retains the pending schedule and effective date")
    func pendingChange() throws {
        var settings = CurfewSettings.default
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        settings.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: settings.schedule,
            requestedAt: now,
            effectiveAt: now.addingTimeInterval(86400),
            classification: .weaker
        )
        let object = try JSONSerialization.jsonObject(with: ScheduleCommand.jsonData(
            settings: settings,
            automaticScheduleEnabled: true
        )) as? [String: Any]
        let pending = try #require(object?["pending_change"] as? [String: Any])
        #expect(pending["effective_at"] as? String == ISO8601DateFormatter()
            .string(from: now.addingTimeInterval(86400)))
        #expect((pending["days"] as? [Any])?.count == 7)
    }
}
