import Foundation
import OSLog

private let widgetMirrorLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "widget-mirror"
)

@MainActor
extension CurfewAppModel {
    func syncWidgetSharedState(_ settings: CurfewSettings? = nil) {
        // Only mirror into the App Group container when the widget is actually
        // enabled. A non-sandboxed app touching the shared container raises the
        // macOS "access data from other apps" prompt, so a default install
        // (widget off) must never write here. Guard before constructing the
        // store so the shared-container URL isn't even resolved.
        guard featureFlags.widgetKitEnabled else { return }
        do {
            try WidgetSharedStateStore().sync(settings: settings ?? self.settings)
        } catch {
            widgetMirrorLogger.error(
                "failed to sync widget shared state: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Writes a live enforcement snapshot the widget can read. Called on
    /// phase transitions in `propagatePhaseTransition` so the widget
    /// timeline reflects the same state the menu-bar icon does, not a
    /// stale settings-derived estimate.
    func syncWidgetEnforcementSnapshot() {
        guard featureFlags.widgetKitEnabled else { return }
        let snapshot = WidgetEnforcementSnapshot(
            phase: snapshotPhaseToken(state.phase),
            minutesRemaining: state.minutesRemaining,
            canRequestExtension: state.canRequestExtension,
            lockDate: state.lockDate,
            unlockDate: state.unlockDate,
            updatedAt: currentTime
        )
        do {
            try WidgetSharedStateStore().sync(enforcement: snapshot)
        } catch {
            widgetMirrorLogger.error(
                "failed to sync widget enforcement: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Stable string tokens for ``EnforcementPhase`` matching the MCP
    /// `curfew.status` vocabulary, so the widget timeline reads the same
    /// labels an AI assistant would.
    private func snapshotPhaseToken(_ phase: EnforcementPhase) -> String {
        switch phase {
        case .working: "working"
        case .warning: "warning"
        case .locked: "locked"
        case .dayOff: "day_off"
        }
    }
}
