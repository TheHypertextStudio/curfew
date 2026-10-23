import CurfewKit
import Foundation

/// Cross-window navigation into the main workspace (`MainWindowView`),
/// requested from a *different* window — currently only Getting Started's
/// "Open Schedule" step, which needs to bring the real `ScheduleView` (a
/// sidebar destination in the main window, not part of the Settings scene)
/// to the front.
@MainActor
extension CurfewAppModel {
    /// Activates the app, ensures the main workspace window exists/is
    /// frontmost, and retains its destination until `MainWindowView` consumes
    /// it, including when that window is being constructed for the first time.
    func requestWorkspaceNavigation(to section: MainWorkspaceSection) {
        appRouter.activate()
        requestedWorkspaceSection = section
        appRouter.openWindow(id: MainWorkspaceSection.windowID)
    }
}
