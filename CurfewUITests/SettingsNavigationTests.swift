import XCTest

extension CurfewUITests {
    @MainActor
    func testSettingsShowsOneCategoryAtATime() {
        let app = launchFixture("settings")
        defer { app.terminate() }

        let presence = app.descendants(matching: .any)["settings-category-presence"]
        XCTAssertTrue(presence.waitForExistence(timeout: 5))
        presence.click()
        XCTAssertTrue(app
            .descendants(matching: .any)["Use the camera to detect whether I'm at my Mac"].exists)
        XCTAssertFalse(app.staticTexts["Extensions and Overrides"].exists)

        app.descendants(matching: .any)["settings-category-enforcement"].click()
        XCTAssertTrue(app.staticTexts["Extensions and Overrides"].exists)
        XCTAssertFalse(app
            .descendants(matching: .any)["Use the camera to detect whether I'm at my Mac"].exists)

        app.descendants(matching: .any)["settings-category-protectedWork"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Let AI assistants declare work in progress"]
            .exists)
        XCTAssertFalse(app.textViews["Application bundle identifiers"].exists)
    }
}
