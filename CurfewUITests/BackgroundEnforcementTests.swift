import XCTest

final class BackgroundEnforcementTests: XCTestCase {
    @MainActor
    func testBackgroundEnforcesWithAllOrdinaryWindowsClosed() {
        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-background-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: report) }
        let app = XCUIApplication()
        app.launchArguments = ["--background"]
        app.launchEnvironment["CURFEW_ACCEPTANCE_REPORT"] = report.path
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = "background-enforcement"
        app.launch()
        defer { app.terminate() }

        XCTAssertFalse(app.windows.firstMatch.waitForExistence(timeout: 2))
        attach("curfew-background-closed-windows")
        let locked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let data = try? Data(contentsOf: report),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return state["phase"] as? String == "locked"
                && state["isEnforcementRunning"] as? Bool == true
                && state["ordinaryWindows"] as? Int == 0
                && (state["lockoutWindows"] as? Int ?? 0) > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [locked], timeout: 12), .completed)
        XCTAssertFalse(app.buttons["main-sidebar-today"].exists)
        attach("curfew-background-lockout")
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
