@testable import curfew_ctl
import Testing

struct CommandParsingTests {
    @Test("Activity accepts the documented day range")
    func activityRange() throws {
        _ = try ActivityCommand.parse(["--days", "7", "--json"])
    }

    @Test("Activity rejects nonpositive ranges")
    func invalidActivityRange() {
        #expect(throws: (any Error).self) {
            _ = try ActivityCommand.parse(["--days", "0"])
        }
    }

    @Test("Reflections reject nonpositive ranges")
    func invalidReflectionRange() {
        #expect(throws: (any Error).self) {
            _ = try ReflectionCommand.parse(["--days", "0"])
        }
    }

    @Test("Schedule accepts its documented show argument")
    func scheduleShow() throws {
        _ = try CurfewCLI.parseAsRoot(["schedule", "show", "--json"])
    }

    @Test("Legacy override fails before it can enqueue a rejected request")
    func unsupportedOverride() {
        #expect(throws: (any Error).self) {
            _ = try OverrideCommand.parse([String(repeating: "emergency reason ", count: 5)])
        }
    }

    @Test("CLI help identifies beta status")
    func betaHelp() {
        #expect(CurfewCLI.configuration.abstract.contains("beta"))
    }
}
