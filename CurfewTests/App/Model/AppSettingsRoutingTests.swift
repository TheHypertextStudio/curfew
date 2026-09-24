@testable import Curfew
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
}
