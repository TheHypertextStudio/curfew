@testable import curfew_ctl
import Testing

struct CLIInstallationCommandTests {
    @Test("Installation is discoverable without a source checkout")
    func setupIsDiscoverable() {
        #expect(CurfewCLI.configuration.subcommands.contains {
            $0.configuration.commandName == "setup"
        })
    }
}
