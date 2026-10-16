import XCTest

extension CurfewUITests {
    @MainActor
    func testPurchaseRestoreAndManualActivationAreReachable() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CURFEW_DEMO_FIXTURE": "1", "CURFEW_DEMO_SCENARIO": "settings",
            "CURFEW_DEMO_STATE": "license-expired"
        ]
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        let restore = app.buttons["Restore Purchase…"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.click()
        XCTAssertTrue(app.textFields["Purchase email"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Send Restore Link"].isEnabled)
        app.buttons["Cancel"].click()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.textFields["Purchase email"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        let available = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: restore
        )
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 3), .completed)
        // The recorded accessibility frame includes leading Form padding.
        // Target the visible arrow inside that frame, not the padding or label.
        app.disclosureTriangles["Enter a license key"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).click()
        XCTAssertTrue(app.textFields["License key"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Activate"].isEnabled)
    }
}
