import AppKit

/// Native visibility can arrive after ordering a window, without another tick.
@MainActor
final class RestWindowVisibilityObserver: NSObject, NSWindowDelegate {
    private let reconcile: () -> Void

    init(reconcile: @escaping () -> Void) {
        self.reconcile = reconcile
    }

    func windowDidChangeOcclusionState(_: Notification) {
        reconcile()
    }
}
