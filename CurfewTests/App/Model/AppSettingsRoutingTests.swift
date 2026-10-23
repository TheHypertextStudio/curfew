@testable import Curfew
@testable import CurfewKit
import Testing

@MainActor
struct AppSettingsRoutingTests {
    @Test("Settings routing invokes the action supplied by the visible SwiftUI scene")
    func settingsRouteUsesSceneAction() {
        let router = SystemAppRouter()
        var openCount = 0

        router.registerSettingsOpener {
            openCount += 1
        }
        router.showSettings()

        #expect(openCount == 1)
    }

    @Test("A Settings request before scene appearance opens once when the scene registers")
    func earlySettingsRequestWaitsForScene() {
        let router = SystemAppRouter()
        var openCount = 0

        router.showSettings()
        router.showSettings()
        router.registerSettingsOpener {
            openCount += 1
        }

        #expect(openCount == 1)
    }

    @Test("Setup requested before any scene exists opens once when actions register")
    func earlySetupRequestWaitsForScene() {
        let router = SystemAppRouter()
        var opened: [String] = []
        router.openWindow(id: CurfewAppModel.gettingStartedWindowID)
        router.openWindow(id: CurfewAppModel.gettingStartedWindowID)

        router.registerWindowActions(open: { opened.append($0) }, dismiss: { _ in })
        router.registerWindowActions(open: { opened.append($0) }, dismiss: { _ in })

        #expect(opened == [CurfewAppModel.gettingStartedWindowID])
    }

    @Test("Setup dismissal uses its own scene action without constructing a main window")
    func setupDismissalDoesNotNeedMainWindow() {
        let router = SystemAppRouter()
        var dismissed: [String] = []
        router.registerWindowActions(open: { _ in }, dismiss: { dismissed.append($0) })

        router.dismissWindow(id: CurfewAppModel.gettingStartedWindowID)

        #expect(dismissed == [CurfewAppModel.gettingStartedWindowID])
    }

    @Test("Dismissing an early setup request cannot reopen it when a scene appears")
    func earlyDismissalSupersedesPendingOpen() {
        let router = SystemAppRouter()
        var opened: [String] = []
        var dismissed: [String] = []
        router.openWindow(id: CurfewAppModel.gettingStartedWindowID)
        router.dismissWindow(id: CurfewAppModel.gettingStartedWindowID)

        router.registerWindowActions(
            open: { opened.append($0) }, dismiss: { dismissed.append($0) }
        )

        #expect(opened.isEmpty)
        #expect(dismissed == [CurfewAppModel.gettingStartedWindowID])
    }

    @Test("Workspace navigation requests opening and retains the last requested section")
    func earlyWorkspaceNavigationRetainsScheduleIntent() {
        let router = AppRouterSpy()
        let model = makeTestAppModel(appRouter: router)

        model.requestWorkspaceNavigation(to: .today)
        model.requestWorkspaceNavigation(to: .schedule)
        #expect(router.openedWindows == [
            MainWorkspaceSection.windowID,
            MainWorkspaceSection.windowID
        ])
        #expect(model.requestedWorkspaceSection == .schedule)
    }

    @Test("Setup actions route opening and Done dismissal without a main-window observer")
    func setupModelActionsRouteWithoutMainWindow() {
        let router = AppRouterSpy()
        let model = makeTestAppModel(appRouter: router)

        model.showGettingStarted()
        model.dismissGettingStarted()

        #expect(router.openedWindows == [CurfewAppModel.gettingStartedWindowID])
        #expect(router.dismissedWindows == [CurfewAppModel.gettingStartedWindowID])
    }
}
