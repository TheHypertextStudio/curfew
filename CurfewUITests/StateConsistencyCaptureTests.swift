import XCTest

extension MarketingCaptureTests {
    @MainActor
    func testCaptureStateConsistency() {
        for appearance in ["light", "dark"] {
            for size in ["default", "minimum"] {
                for (scenario, state) in [
                    ("overview", "today-off-locked"),
                    ("getting-started", "setup-review"),
                    ("getting-started", "setup-review-denied"),
                    ("settings", "assistant-malformed")
                ] {
                    let app = launch(scenario, state: state, appearance: appearance, size: size)
                    if state == "assistant-malformed" {
                        let review = app.buttons["review-ai-request"]
                        XCTAssertTrue(review.waitForExistence(timeout: 5))
                        review.click()
                        let approve = app.buttons["Approve"]
                        XCTAssertTrue(approve.waitForExistence(timeout: 5))
                        XCTAssertFalse(approve.isEnabled)
                        assertText("Request unavailable", in: app)
                        let sheet = app.sheets.firstMatch
                        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
                        attach(sheet, name: "\(state)-\(appearance)-\(size)")
                    } else {
                        let prefix = scenario == "getting-started"
                            ? "getting-started" : "main-workspace"
                        let window = app.windows.matching(NSPredicate(
                            format: "identifier BEGINSWITH %@", prefix
                        )).firstMatch
                        XCTAssertTrue(window.waitForExistence(timeout: 8))
                        if state == "today-off-locked" {
                            assertText("Curfew is off. Review your schedule.", in: app)
                            XCTAssertTrue(app.buttons["Turn on Curfew"].exists)
                            XCTAssertFalse(app.staticTexts["Curfew is active."].exists)
                        } else {
                            assertText("Review setup", in: app)
                            assertText("Curfew is off.", in: app)
                            XCTAssertTrue(app.buttons["Done"].exists)
                            XCTAssertFalse(app.buttons["Finish Setup"].exists)
                            if state == "setup-review-denied" {
                                XCTAssertTrue(app.buttons["Open System Settings"].exists)
                            }
                        }
                        attach(window, name: "\(state)-\(appearance)-\(size)")
                    }
                    app.terminate()
                }
            }
        }
    }
}
