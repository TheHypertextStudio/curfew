import AppKit
@testable import Curfew
import Testing

@MainActor
struct BackgroundIntegrationRegressionTests {
    @Test func closingLastWindowExplicitlyKeepsEnforcementProcessAlive() {
        let delegate: any NSApplicationDelegate = AppDelegate()
        #expect(delegate
            .applicationShouldTerminateAfterLastWindowClosed?(NSApplication.shared) == false)
    }
}
