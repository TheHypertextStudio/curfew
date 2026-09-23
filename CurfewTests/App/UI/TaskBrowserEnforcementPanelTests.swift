@testable import Curfew
import Testing

struct TaskBrowserEnforcementPanelTests {
    @Test func studioDevelopmentExplainsChromeIsUnavailableOnlyHere() {
        #expect(TaskBrowserPanelCopy.availabilityMessage(for: .studioDevelopment)
            == "Chrome task-browser enforcement is unavailable in this Studio Dev build.")
        #expect(TaskBrowserPanelCopy.availabilityMessage(for: .development) == nil)
        #expect(TaskBrowserPanelCopy.availabilityMessage(for: .production) == nil)
    }

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
