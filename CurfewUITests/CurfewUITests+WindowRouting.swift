import XCTest

extension CurfewUITests {
    @MainActor
    func testSetupReviewOpensAndDismissesWithoutMainWindow() {
        let app = launchFixture("settings", state: "ready", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        app.buttons["Review Setup…"].click()
        let setup = app.windows["Set Up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        XCTAssertTrue(setup.staticTexts["Review setup"].exists)
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.windows["Curfew"].exists)

        app.buttons["Review Setup…"].click()
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testMenuOpenedSetupDismissesWithoutMainWindow() {
        let app = launchFixture("settings", state: "ready", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Set Up Curfew"].click()
        let setup = app.windows["Set Up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.windows["Curfew"].exists)
    }

    @MainActor
    func testFirstRunScheduleOpensNewMainWindow() {
        let app = launchFixture("getting-started", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Set Up Curfew"].click()
        let setup = app.windows["Set Up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Next"].click()
        setup.buttons["Edit weekly schedule"].click()
        let workspace = app.windows["Curfew"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        XCTAssertTrue(workspace.staticTexts["Weekly schedule"].waitForExistence(timeout: 5))
    }
}
