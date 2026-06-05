import Foundation

extension MainWorkspaceSection {
    /// The sidebar section the main window selects on first appearance.
    ///
    /// Normally ``overview``. In Debug, a demo-capture launch
    /// (`CURFEW_DEMO_FIXTURE=1` + `CURFEW_DEMO_SCENARIO=…`) can pin a
    /// different starting section so a screenshot lands on the right pane.
    /// Always ``overview`` in Release — the demo machinery is `#if DEBUG`.
    static var demoLaunchSelection: MainWorkspaceSection {
        #if DEBUG
            if let scenario = CurfewLaunchBehavior.demoScenario(
                environment: ProcessInfo.processInfo.environment
            ) {
                return scenario.initialSection ?? .overview
            }
        #endif
        return .overview
    }
}
