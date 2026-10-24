import XCTest

@MainActor
extension MarketingCaptureTests {
    func testCaptureAStateConsistencyOffLocked() {
        captureStateConsistency("overview", state: "today-off-locked")
    }

    func testCaptureAStateConsistencySetupReview() {
        captureStateConsistency("getting-started", state: "setup-review")
    }

    func testCaptureAStateConsistencySetupPermission() {
        captureStateConsistency("getting-started", state: "setup-review-denied")
    }

    func testCaptureAStateConsistencyExhaustedRequest() {
        captureStateConsistency("settings", state: "assistant-exhausted")
    }

    func testCaptureAStateConsistencyMalformedRequest() {
        captureStateConsistency("settings", state: "assistant-malformed")
    }

    func testCaptureAStateConsistencyAccountOffline() {
        captureStateConsistency("settings", state: "account-offline")
    }

    func testCaptureAStateConsistencyAccountSignIn() {
        captureStateConsistency("settings", state: "account-sign-in-required")
    }

    func testCaptureAStateConsistencyAccountHelper() {
        captureStateConsistency("settings", state: "account-helper-unavailable")
    }

    func testCaptureAStateConsistencyAccountUpdate() {
        captureStateConsistency("settings", state: "account-update-failed")
    }

    func testCaptureAStateConsistencyAccountUnavailable() {
        captureStateConsistency("settings", state: "account-helper-hidden")
    }

    private func captureStateConsistency(_ scenario: String, state: String) {
        for appearance in ["light", "dark"] {
            for size in ["default", "minimum"] {
                let app = launch(scenario, state: state, appearance: appearance, size: size)
                if state.hasPrefix("account-") {
                    captureAccountState(app, state: state, appearance: appearance, size: size)
                } else if state == "assistant-malformed" || state == "assistant-exhausted" {
                    let review = app.buttons["review-ai-request"]
                    XCTAssertTrue(review.waitForExistence(timeout: 5))
                    review.click()
                    let approve = app.buttons["Approve"]
                    XCTAssertTrue(approve.waitForExistence(timeout: 5))
                    XCTAssertFalse(approve.isEnabled)
                    assertText("Request unavailable", in: app)
                    if state == "assistant-exhausted" {
                        assertText("No extensions left this week.", in: app)
                        XCTAssertTrue(app.buttons["Deny"].isEnabled)
                    }
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

    private func captureAccountState(
        _ app: XCUIApplication, state: String, appearance: String, size: String
    ) {
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        switch state {
        case "account-offline": assertText("Remote control is offline", in: app)
        case "account-sign-in-required":
            assertText("Reconnect this Mac to Curfew", in: app)
            XCTAssertTrue(
                app.buttons["Sign in again to reconnect this Mac"].exists,
                app.debugDescription
            )
        case "account-update-failed":
            assertText("Remote update couldn’t be applied", in: app)
            XCTAssertFalse(
                app.staticTexts["Check this Mac’s account access"].exists,
                app.debugDescription
            )
        case "account-helper-hidden":
            assertText("Remote locks are unavailable", in: app)
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(identifier: "settings-get-curfew").firstMatch.exists,
                app.debugDescription
            )
        default: assertText("Remote locks are not ready", in: app)
        }
        if state == "account-helper-hidden" {
            XCTAssertFalse(app.buttons["Review Background Protection"].exists, app.debugDescription)
        } else {
            XCTAssertTrue(app.buttons["Review Background Protection"].exists, app.debugDescription)
        }
        XCTAssertFalse(app.buttons["Install Background Protection…"].exists, app.debugDescription)
        attach(window, name: "\(state)-\(appearance)-\(size)")
    }

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
            XCTAssertTrue(app.buttons["Turn on Curfew"].exists, app.debugDescription)
            XCTAssertFalse(app.staticTexts["Curfew is active."].exists, app.debugDescription)
        } else {
            assertText("Review setup", in: app)
            assertText("Automatic weekly lockouts are off.", in: app)
            assertText("Authorized remote locks can still apply.", in: app)
            XCTAssertTrue(app.buttons["Done"].exists, app.debugDescription)
            XCTAssertFalse(app.buttons["Finish Setup"].exists, app.debugDescription)
            if state == "setup-review-denied" {
                XCTAssertTrue(app.buttons["Open System Settings"].exists, app.debugDescription)
            }
        }
        attach(window, name: "\(state)-\(appearance)-\(size)")
    }
}
