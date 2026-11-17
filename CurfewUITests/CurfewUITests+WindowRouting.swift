import XCTest

@MainActor
extension CurfewUITests {
    func testSetupReviewOpensAndDismissesWithoutMainWindow() {
        let app = launchFixture("settings", state: "ready", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        app.buttons["Review setup…"].click()
        let setup = app.windows["Set up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        XCTAssertTrue(setup.staticTexts["You're set."].exists)
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.windows["Curfew"].exists)

        app.buttons["Review setup…"].click()
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
    }

    func testMenuOpenedSetupDismissesWithoutMainWindow() {
        let app = launchFixture("settings", state: "ready", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Set up Curfew"].click()
        let setup = app.windows["Set up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Done"].click()
        XCTAssertTrue(setup.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.windows["Curfew"].exists)
    }

    func testFirstRunSetupOpensWithoutMainWindow() {
        let app = launchFixture("getting-started", withoutMainWindow: true)
        XCTAssertFalse(app.windows["Curfew"].exists)
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Set up Curfew"].click()
        let setup = app.windows["Set up Curfew"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        XCTAssertTrue(setup.staticTexts["When should this Mac close for the night?"]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows["Curfew"].exists)
    }
}
