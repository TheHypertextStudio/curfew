import XCTest

final class CurfewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingStartsAtARealGate() {
        let app = launchFixture("getting-started")

        XCTAssertTrue(app.staticTexts["Welcome to Curfew"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)
        XCTAssertFalse(app.buttons["Back"].isEnabled)
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        XCTAssertTrue(app.buttons["Not now"].exists)
    }

    @MainActor
    func testWarningAndLockoutPresentation() {
        var app = launchFixture("warning")
        XCTAssertTrue(app.staticTexts["warning-countdown"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["warning-countdown"].label, "2 min")
        app.terminate()

        app = launchFixture("lockout")
        XCTAssertTrue(app.otherElements["lockout-screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["override-entry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOverrideRequiresCooldownReasonAndHold() {
        let app = launchFixture("lockout")
        let entry = app.buttons["override-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()

        XCTAssertTrue(app.textViews["override-reason"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["override-cooldown"].exists)
        XCTAssertTrue(app.staticTexts["Minimum 50 characters"].exists)
        let hold = app.buttons["override-hold-confirm"]
        XCTAssertTrue(hold.exists)
        XCTAssertFalse(hold.isEnabled, "Hold confirmation must stay disabled during cooldown.")
    }

    @MainActor
    func testShippingIntegrationsAndHelperFailureAreVisible() {
        let app = launchFixture("settings")
        let integrations = app.descendants(matching: .any)["settings-integrations-tab"]
        XCTAssertTrue(integrations.waitForExistence(timeout: 8))
        integrations.tap()

        XCTAssertTrue(app.staticTexts["WidgetKit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LaunchDaemon"].exists)
        XCTAssertTrue(app.staticTexts["Authenticated channel: Unavailable"].exists)
        XCTAssertTrue(app
            .staticTexts[
                "The privileged helper is unavailable. Install or approve it in System Settings."
            ]
            .exists)
        XCTAssertFalse(app.staticTexts["Calendar"].exists)
        XCTAssertFalse(app.staticTexts["Cloud Sync"].exists)
    }

    @MainActor
    func testSparkleUpdateCommandIsPresent() {
        let app = launchFixture("overview")
        let appMenu = app.menuBars.menuBarItems["Curfew"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 8))
        appMenu.click()
        XCTAssertTrue(app.menuItems["Check for Updates…"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchFixture(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = scenario
        app.launch()
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }
}
