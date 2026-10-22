import XCTest

@MainActor
extension CurfewUITests {
    func testRestScreenOffersExplicitCompanionSetupAndSystemSelection() {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-restScreen-tab"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()

        let detail = app.descendants(matching: .any)["settings-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let install = app.buttons["rest-saver-install"]
        let settings = app.buttons["rest-saver-settings"]
        XCTAssertTrue(
            install.waitForExistence(timeout: 3),
            "Rest Screen must expose an explicit companion setup action."
        )
        for _ in 0 ..< 6 where !install.isHittable || !settings.isHittable {
            detail.scroll(byDeltaX: 0, deltaY: -250)
        }
        XCTAssertTrue(install.isHittable)
        XCTAssertTrue(
            settings.exists,
            "User selection must remain an explicit System Settings action."
        )
        XCTAssertTrue(settings.isHittable)
        // Do not activate either action: this test must never invoke a native installer or
        // preference pane.
    }
}
