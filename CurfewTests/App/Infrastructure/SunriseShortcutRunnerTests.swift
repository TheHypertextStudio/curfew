@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Shortcut runner speaks to the system's `shortcuts` command through an
/// injected launcher, so no test lists or runs a real Shortcut.
struct SunriseShortcutRunnerTests {
    @Test("Listing reads names and identifiers from the shortcuts command")
    func listsShortcuts() async {
        let launcher = RecordingShortcutLauncher(status: 0, output: """
        Plan my day (1A2B3C4D-0000-0000-0000-000000000001)
        Focus (work) (1A2B3C4D-0000-0000-0000-000000000002)

        not a shortcut line
        """)
        let shortcuts = await SunriseShortcutRunner(launcher: launcher).list()
        #expect(shortcuts == [
            SunriseShortcut(
                identifier: "1A2B3C4D-0000-0000-0000-000000000001",
                name: "Plan my day"
            ),
            SunriseShortcut(
                identifier: "1A2B3C4D-0000-0000-0000-000000000002",
                name: "Focus (work)"
            )
        ])
        #expect(await launcher.calls.first?.arguments == ["list", "--show-identifiers"])
    }

    @Test("Listing that fails yields no shortcuts")
    func listFailure() async {
        let shortcuts = await SunriseShortcutRunner(
            launcher: RecordingShortcutLauncher(status: 1, output: "Plan (X)")
        ).list()
        #expect(shortcuts.isEmpty)
    }

    @Test("Running passes the one thing as a text file and removes it afterwards")
    func runsWithTextInput() async throws {
        let launcher = RecordingShortcutLauncher(status: 0)
        let ran = await SunriseShortcutRunner(launcher: launcher).run(
            SunriseShortcut(identifier: "ID", name: "Plan"), input: "Ship it"
        )
        #expect(ran)
        let call = try #require(await launcher.calls.first)
        #expect(call.arguments.prefix(2) == ["run", "ID"])
        #expect(call.input == "Ship it")
        let path = try #require(call.arguments.last)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("A nonzero exit is a failed run")
    func runFailure() async {
        let ran = await SunriseShortcutRunner(launcher: RecordingShortcutLauncher(status: 2)).run(
            SunriseShortcut(identifier: "ID", name: "Plan"), input: "x"
        )
        #expect(!ran)
    }

    @Test("The test host never reaches the real shortcuts command")
    func inertInTests() {
        #expect(SunriseShortcutRunner.live.isInert)
    }
}
