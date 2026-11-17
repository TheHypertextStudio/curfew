import XCTest

@MainActor
extension CurfewUITests {
    func testSettingsShowsOneCategoryAtATime() {
        let app = launchFixture("settings")
        defer { app.terminate() }

        let presence = app.descendants(matching: .any)["settings-category-presence"]
        XCTAssertTrue(presence.waitForExistence(timeout: 5))
        presence.click()
        XCTAssertTrue(app
            .descendants(matching: .any)["Use the camera to tell whether I'm at my Mac"].exists)
        XCTAssertFalse(app.staticTexts["More time and overrides"].exists)

        app.descendants(matching: .any)["settings-category-enforcement"].click()
        XCTAssertTrue(app.staticTexts["More time and overrides"].exists)
        XCTAssertFalse(app
            .descendants(matching: .any)["Use the camera to tell whether I'm at my Mac"].exists)

        app.descendants(matching: .any)["settings-category-protectedWork"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Let AI assistants declare work in progress"]
            .exists)
        XCTAssertFalse(app.textViews["Application bundle identifiers"].exists)
    }

    /// The default settings fixture has no Curfew helper installed. Protection
    /// states that once, in the Curfew helper row, with the action that fixes it.
    func assertHelperFailureIsStated(
        in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["Curfew helper"].waitForExistence(timeout: 3), file: file, line: line
        )
        XCTAssertTrue(app.staticTexts["Needs attention"].exists, file: file, line: line)
        XCTAssertTrue(app.staticTexts[
            "The Curfew helper isn't set up, so curfew only holds while Curfew is open."
        ].exists, file: file, line: line)
        XCTAssertTrue(app.buttons["Set up the Curfew helper"].exists, file: file, line: line)
    }
}
