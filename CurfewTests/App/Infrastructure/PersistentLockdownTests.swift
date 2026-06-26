@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Behaviour tests for `PersistentLockdown` — the LaunchAgent-backed
/// respawn-on-kill deterrent.
///
/// Tests exercise plist generation + filesystem install paths in a
/// temp directory. They do NOT invoke real `launchctl` because that
/// would mutate the developer's `launchd` state. The
/// `LaunchctlRunner` abstraction handles the process boundary so
/// tests can verify we *would* run the right subcommand without
/// actually running it.
@MainActor
struct PersistentLockdownTests {
    @Test("Generated plist contains the expected label and trigger path")
    func plistContainsExpectedKeys() throws {
        let directory = try ephemeralDirectory(label: "plist-keys")
        let lockdown = PersistentLockdown(
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            triggerPath: directory.appendingPathComponent("trigger"),
            curfewExecutableURL: URL(
                fileURLWithPath: "/Applications/Curfew.app/Contents/MacOS/Curfew"
            ),
            launchctl: RecordingLaunchctl()
        )

        let dict = lockdown.renderPlist()

        #expect(dict["Label"] as? String == PersistentLockdown.agentLabel)
        #expect(dict["RunAtLoad"] as? Bool == false)
        let programArguments = try #require(dict["ProgramArguments"] as? [String])
        #expect(programArguments.first == "/Applications/Curfew.app/Contents/MacOS/Curfew")

        let keepAlive = try #require(dict["KeepAlive"] as? [String: Any])
        let pathState = try #require(keepAlive["PathState"] as? [String: Bool])
        let triggerPath = directory.appendingPathComponent("trigger").path
        #expect(pathState[triggerPath] == true)
    }

    @Test("Install writes the plist and invokes launchctl load")
    func installWritesPlistAndLoads() throws {
        let directory = try ephemeralDirectory(label: "install")
        let launchAgents = directory.appendingPathComponent("LaunchAgents")
        let runner = RecordingLaunchctl()
        let lockdown = PersistentLockdown(
            launchAgentsDirectory: launchAgents,
            triggerPath: directory.appendingPathComponent("trigger"),
            curfewExecutableURL: URL(fileURLWithPath: "/usr/local/bin/Curfew"),
            launchctl: runner
        )

        try lockdown.install()

        let plistURL = launchAgents.appendingPathComponent(
            "\(PersistentLockdown.agentLabel).plist"
        )
        #expect(FileManager.default.fileExists(atPath: plistURL.path))
        #expect(runner.invocations == [["load", plistURL.path]])
    }

    @Test("Uninstall removes the plist and invokes launchctl unload")
    func uninstallRemovesPlistAndUnloads() throws {
        let directory = try ephemeralDirectory(label: "uninstall")
        let launchAgents = directory.appendingPathComponent("LaunchAgents")
        let runner = RecordingLaunchctl()
        let lockdown = PersistentLockdown(
            launchAgentsDirectory: launchAgents,
            triggerPath: directory.appendingPathComponent("trigger"),
            curfewExecutableURL: URL(fileURLWithPath: "/usr/local/bin/Curfew"),
            launchctl: runner
        )

        try lockdown.install()
        runner.invocations.removeAll()
        try lockdown.uninstall()

        let plistURL = launchAgents.appendingPathComponent(
            "\(PersistentLockdown.agentLabel).plist"
        )
        #expect(!FileManager.default.fileExists(atPath: plistURL.path))
        #expect(runner.invocations == [["unload", plistURL.path]])
    }

    @Test("Arm creates the trigger file, disarm removes it")
    func armDisarmTogglesTriggerFile() throws {
        let directory = try ephemeralDirectory(label: "arm")
        let trigger = directory.appendingPathComponent("trigger")
        let lockdown = PersistentLockdown(
            launchAgentsDirectory: directory.appendingPathComponent("LaunchAgents"),
            triggerPath: trigger,
            curfewExecutableURL: URL(fileURLWithPath: "/usr/local/bin/Curfew"),
            launchctl: RecordingLaunchctl()
        )

        #expect(!FileManager.default.fileExists(atPath: trigger.path))
        try lockdown.arm()
        #expect(FileManager.default.fileExists(atPath: trigger.path))
        try lockdown.disarm()
        #expect(!FileManager.default.fileExists(atPath: trigger.path))
    }

    // MARK: - Helpers

    private func ephemeralDirectory(label: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(
            "curfew-lockdown-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private final class RecordingLaunchctl: LaunchctlRunning {
    var invocations: [[String]] = []

    func run(arguments: [String]) throws {
        invocations.append(arguments)
    }
}
