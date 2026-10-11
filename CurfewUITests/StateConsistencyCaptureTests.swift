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
                    ("settings", "assistant-malformed"),
                    ("settings", "account-offline"),
                    ("settings", "account-sign-in-required"),
                    ("settings", "account-helper-unavailable"),
                    ("settings", "account-update-failed"),
                    ("settings", "account-helper-hidden")
                ] {
                    let app = launch(scenario, state: state, appearance: appearance, size: size)
                    if state.hasPrefix("account-") {
                        captureAccountState(app, state: state, appearance: appearance, size: size)
                    } else if state == "assistant-malformed" {
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
                        captureSetupState(
                            app, scenario: scenario, state: state, appearance: appearance,
                            size: size
                        )
                    }
                    app.terminate()
                }
            }
        }
    }

    @MainActor
    private func captureAccountState(
        _ app: XCUIApplication, state: String, appearance: String, size: String
    ) {
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        switch state {
        case "account-offline": assertText("Remote control is offline", in: app)
        case "account-sign-in-required":
            assertText("Reconnect this Mac to Curfew", in: app)
            XCTAssertTrue(app.buttons["Sign in again to reconnect this Mac"].exists)
        case "account-update-failed":
            assertText("Remote update couldn’t be applied", in: app)
            XCTAssertFalse(app.staticTexts["Check this Mac’s account access"].exists)
        case "account-helper-hidden":
            assertText("Remote locks are unavailable", in: app)
        default: assertText("Remote locks are not ready", in: app)
        }
        if state == "account-helper-hidden" {
            XCTAssertFalse(app.buttons["Review Background Protection"].exists)
        } else {
            XCTAssertTrue(app.buttons["Review Background Protection"].exists)
        }
        XCTAssertFalse(app.buttons["Install Background Protection…"].exists)
        attach(window, name: "\(state)-\(appearance)-\(size)")
    }

    @MainActor
    private func captureSetupState(
        _ app: XCUIApplication, scenario: String, state: String, appearance: String, size: String
    ) {
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
}
