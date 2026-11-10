import AppKit
@testable import Curfew
import Testing

@MainActor
struct RestVisibilityTests {
    @Test("Visibility follows the authenticated session independently of foreground focus")
    func visibleInactiveAppCanResume() {
        let coordinator = OverlayCoordinator()
        coordinator.restDisplaysHidden()
        #expect(!coordinator.restCanReveal)
        coordinator.restDisplaysWoke()
        #expect(coordinator.restCanReveal)
        coordinator.restSessionResigned()
        coordinator.restDisplaysWoke()
        #expect(!coordinator.restCanReveal)
        coordinator.restSessionActivated()
        #expect(coordinator.restCanReveal)
    }
}
