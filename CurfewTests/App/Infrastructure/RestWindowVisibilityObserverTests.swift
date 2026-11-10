import AppKit
@testable import Curfew
import Testing

@MainActor
struct RestWindowVisibilityObserverTests {
    @Test("Native occlusion changes request reconciliation without a clock tick")
    func nativeVisibilityRequestsReconciliation() {
        var calls = 0
        let observer = RestWindowVisibilityObserver { calls += 1 }
        observer.windowDidChangeOcclusionState(Notification(
            name: NSWindow.didChangeOcclusionStateNotification
        ))
        #expect(calls == 1)
    }
}
