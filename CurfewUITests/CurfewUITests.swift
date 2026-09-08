import XCTest

final class CurfewUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in
        // the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation -
        // required for your tests before they run.
        // The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in
        // the class.
    }

    @MainActor
    func testTaskBrowserEnforcementPanelActions() {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = "settings"
        app.launch()

        XCTAssertTrue(app.staticTexts["Task Browser Enforcement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Complete LVBT social strategy"].exists)
        XCTAssertTrue(app.staticTexts["instagram.com"].exists)

        let enforcementToggle = app.switches["task-browser-enforcement-toggle"]
        XCTAssertTrue(enforcementToggle.isEnabled)

        let breakButton = app.buttons["task-browser-break-button"]
        XCTAssertTrue(breakButton.isEnabled)
        breakButton.click()
        XCTAssertTrue(app.staticTexts["Break ends"].waitForExistence(timeout: 2))

        let removeButton = app.buttons["Remove instagram.com"]
        XCTAssertTrue(removeButton.exists)
        removeButton.click()
        XCTAssertFalse(app.staticTexts["instagram.com"].exists)
    }

    @MainActor
    func testLaunchPerformance() {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
