@testable import curfew_mcp
import CurfewKit
import Foundation
import Testing

struct CurfewMCPAccessTests {
    @Test("Local schedule tool labels saved rules inactive when weekly consent is off")
    func inactiveScheduleIsLabeled() throws {
        let suiteName = "CurfewSettingsStoreTests.MCPScheduleConsent.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.schedule.rules[.monday]?.mode = .hours
        settings.schedule.rules[.monday]?.hoursLimitMinutes = 6 * 60
        store.save(settings)

        let content = try #require(MCPTool.makeSchedule(
            settingsStore: store,
            flavor: .development
        ).call([:]).first)
        let text = try #require(content["text"] as? String)
        #expect(text.contains("Automatic weekly schedule: off"))
        #expect(text.contains("Saved weekly schedule:"))
        #expect(text.contains("Mon: locks after 6 h of work; unlocks at 06:00"))
    }

    @Test("Local MCP read tools use fresh app observations, not schedule predictions")
    func readToolsUseObservedStatus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-mcp-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CurfewObservedStatusStore(
            fileURL: directory.appendingPathComponent("status.json")
        )
        let now = Date()
        try store.save(CurfewObservedStatus(
            evaluation: .locked(
                lockDate: now.addingTimeInterval(-60),
                unlockDate: now.addingTimeInterval(240)
            ),
            observedAt: now,
            enforcementRunning: false,
            ownsLockout: false
        ))

        let status = try #require(MCPTool.makeStatus(store: store).call([:]).first)
        #expect((status["text"] as? String)?.contains("Phase: unknown") == true)
        #expect((status["text"] as? String)?.contains("Unlocks:") == false)

        let countdown = try #require(MCPTool.makeTimeRemaining(store: store).call([:]).first)
        let countdownText = try #require(countdown["text"] as? String)
        let payload = try #require(
            JSONSerialization.jsonObject(with: Data(countdownText.utf8)) as? [String: Any]
        )
        #expect(payload["phase"] as? String == "unknown")
        #expect(payload["minutes"] == nil)

        try store.save(CurfewObservedStatus(
            evaluation: .locked(
                lockDate: now.addingTimeInterval(-60),
                unlockDate: now.addingTimeInterval(240), trigger: .hours
            ),
            observedAt: now, enforcementRunning: true, ownsLockout: true,
            mode: .hours
        ))
        let hoursContent = try #require(MCPTool.makeTimeRemaining(store: store).call([:]).first)
        let hoursText = try #require(hoursContent["text"] as? String)
        let hoursPayload = try #require(
            JSONSerialization.jsonObject(with: Data(hoursText.utf8)) as? [String: Any]
        )
        #expect(hoursPayload["mode"] as? String == "hours")
        #expect(hoursPayload["trigger"] as? String == "hours")
    }

    @Test("Disabled local access hides tools and rejects cached calls")
    func disabledAccessClosesBothDispatcherPaths() throws {
        let server = MCPServer(isAccessEnabled: { false })

        let list = try response(
            from: server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        )
        let result = try #require(list["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(tools.isEmpty)

        let call = try response(
            from: server.handle(
                line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"curfew_get_reflections","arguments":{}}}"#
            )
        )
        let error = try #require(call["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32001)
        #expect((error["message"] as? String)?.contains("turned off") == true)
    }

    private func response(from line: String?) throws -> [String: Any] {
        let line = try #require(line)
        let data = try #require(line.data(using: .utf8))
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
