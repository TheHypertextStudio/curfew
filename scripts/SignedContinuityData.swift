import Darwin
import Foundation

/// Synthetic data only, compiled beside the immutable producer's library sources.
/// This is never linked into, injected into, or substituted for the signed app.
@main
struct SignedContinuityData {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        guard let account = getpwuid(geteuid()), geteuid() >= 500,
              String(cString: account.pointee.pw_name) == "runner",
              String(cString: account.pointee.pw_dir) == "/Users/runner",
              env["GITHUB_ACTIONS"] == "true", env["RUNNER_ENVIRONMENT"] == "github-hosted",
              env["HOME"] == "/Users/runner",
              env["RUNNER_TEMP"] == "/Users/runner/work/_temp",
              CommandLine.arguments.count == 2 else { exit(64) }
        let root = URL(fileURLWithPath: "/Users/runner/work/_temp/signed-continuity")
        let owner = try JSONSerialization
            .jsonObject(with: Data(contentsOf: root
                    .appendingPathComponent("owner.json"))) as? [String: Any]
        guard owner?["uid"] as? UInt32 == geteuid(),
              owner?["runID"] as? String == env["GITHUB_RUN_ID"],
              owner?["harnessSourceCommit"] as? String == env["GITHUB_SHA"] else { exit(64) }
        let support = URL(fileURLWithPath: "/Users/runner/Library/Application Support/Curfew")
        guard support.resolvingSymlinksInPath() == support else { exit(64) }
        let defaults = UserDefaults(suiteName: "studio.hypertext.curfew")!
        let settingsStore = CurfewSettingsStore(defaults: defaults)
        let action = CommandLine.arguments[1]
        if action == "seed" {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            var settings = CurfewSettings.default
            settings.hasCompletedInitialSetup = false
            settings.autoShutdownEnabled = false
            settings.mcpEnabled = false
            settings.extensionWeeklyLimit = 7
            settingsStore.save(settings)
            settingsStore.saveAutomaticScheduleConsent(false)
            let now = Date(), parts = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: now
            )
            try EnforcementRuntimeStateStore(recordURL: support
                .appendingPathComponent("enforcement-runtime.json")).save(
                EnforcementRuntimeState(
                    dayToken: "\(parts.year!)-\(parts.month!)-\(parts.day!)",
                    extensionUses: 2,
                    overrideUses: 1,
                    extensionResetBoundary: now,
                    overrideResetBoundary: now
                )
            )
        }
        let settings = settingsStore.load()
        guard !settings.hasCompletedInitialSetup, !settings.autoShutdownEnabled,
              !settings.mcpEnabled,
              settingsStore.loadAutomaticScheduleConsent() == false,
              settings.extensionWeeklyLimit == 7 else { exit(65) }
        let activity = try ActivityStore(directory: support)
        let reflections = try ReflectionStore(databaseURL: support
            .appendingPathComponent("reflections.sqlite3"))
        if action == "seed" || action == "append" {
            let index = action == "seed" ? 1 : 2
            let text = "Signed continuity synthetic \(index)"
            try activity.append(ActivityEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                timestamp: Date().addingTimeInterval(-1),
                gateKind: GateKind.curfew,
                kind: .extensionGranted,
                minutesValue: index * 15,
                note: text
            ))
            try reflections.append(Reflection(
                id: UUID(uuidString: "10000000-0000-0000-0000-00000000000\(index)")!,
                timestamp: Date().addingTimeInterval(-1),
                gate: .evening,
                answers: [ReflectionAnswer(
                    promptID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                    promptTextSnapshot: "Synthetic prompt",
                    value: .text(text)
                )]
            ))
        } else if action != "snapshot" {
            exit(64)
        }
        let encoder = JSONEncoder()
        let eventRows: [[String: Any]] = try activity.events(in: .distantPast ... .distantFuture)
            .filter { $0.note?.hasPrefix("Signed continuity synthetic") == true }
            .map { [
                "id": $0.id.uuidString,
                "note": $0.note!,
                "minutes": $0.minutesValue!,
                "timestamp": $0.timestamp.timeIntervalSince1970
            ] }
        let reflectionRows = try reflections.reflections(in: .distantPast ... .distantFuture)
            .filter {
                $0.answers
                    .contains {
                        if case .text(let text) = $0
                            .value {
                            return text.hasPrefix("Signed continuity synthetic")
                        }; return false
                    }
            }
        let runtime = try EnforcementRuntimeStateStore(recordURL: support
            .appendingPathComponent("enforcement-runtime.json")).load()!
        let snapshot: [String: Any] = try [
            "settings": JSONSerialization.jsonObject(with: encoder.encode(settings)),
            "runtime": JSONSerialization.jsonObject(with: encoder.encode(runtime)),
            "automaticScheduleConsent": false,
            "events": eventRows,
            "reflections": JSONSerialization.jsonObject(with: encoder.encode(reflectionRows))
        ]
        defaults.synchronize()
        try print(String(
            data: JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
            encoding: .utf8
        )!)
    }
}
