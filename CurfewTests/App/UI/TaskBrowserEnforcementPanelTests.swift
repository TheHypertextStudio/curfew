@testable import Curfew
import Testing

struct TaskBrowserEnforcementPanelTests {
    @Test("The browser panel names the one supported setup and mapping workflow")
    func panelCopyStaysTaskScoped() {
        #expect(TaskBrowserPanelCopy.title == "Task Browser Enforcement")
        #expect(TaskBrowserPanelCopy.connectAction == "Connect Docket")
        #expect(TaskBrowserPanelCopy.breakAction == "Take 15-minute break")
        #expect(TaskBrowserPanelCopy.mappingAction == "Add destination")
        #expect(TaskBrowserPanelCopy.selectorKinds == ["Task", "Project", "Label"])
        #expect(TaskBrowserPanelCopy.scopeKinds == ["Origin", "Path prefix"])
    }
}
