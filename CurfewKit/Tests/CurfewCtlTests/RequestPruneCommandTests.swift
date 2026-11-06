import ArgumentParser
@testable import curfew_ctl
import Foundation
import Testing

struct RequestPruneCommandTests {
    @Test("Resolved request maintenance is available without a source checkout")
    func registeredCommand() throws {
        let command = try CurfewCLI.parseAsRoot(["request", "prune", "--json"])
        #expect(type(of: command)._commandName == "prune")
    }
}
