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
        let manualEntry = app.buttons["Enter a license key"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 3))
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
        manualEntry.click()
        XCTAssertEqual(manualEntry.value as? String, "Expanded")
        XCTAssertTrue(app.textFields["license-key-input"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Activate"].isEnabled)

        app.textFields["license-key-input"].click()
        app.textFields["license-key-input"].typeText("not-a-license")
        app.buttons["Activate"].click()
        let invalidKey = "The license key format is invalid."
        XCTAssertTrue(app.staticTexts[invalidKey].waitForExistence(timeout: 3))
        restore.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.textFields["Purchase email"].waitForExistence(timeout: 3))
        XCTAssertFalse(
            sheet.staticTexts[invalidKey].exists,
            "A manual activation error must not appear in a new restoration form."
        )
        XCTAssertFalse(sheet.buttons["Send Restore Link"].isEnabled)
        sheet.buttons["Cancel"].click()
    }
}
