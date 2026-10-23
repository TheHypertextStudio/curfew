import XCTest

/// Runs only in the isolated signed-installer lane, against the installed Developer ID app.
final class SignedInstallerAcceptanceTests: XCTestCase {
    @MainActor
    func testFreshSignedInstallerOpensRealSetup() throws {
        try XCTSkipUnless(ProcessInfo.processInfo
            .environment["CURFEW_SIGNED_INSTALLER_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        let bundle = try XCTUnwrap(Bundle(path: "/Applications/Curfew.app"))
        XCTAssertEqual(bundle.bundleIdentifier, "studio.hypertext.apps.curfew")
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            ProcessInfo.processInfo.environment["CURFEW_SIGNED_INSTALLER_VERSION"]
        )
        let app = XCUIApplication(bundleIdentifier: "studio.hypertext.apps.curfew")
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Welcome to Curfew"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        XCTAssertTrue(app.buttons["Not now"].exists)
        attachScreenshot(of: app, named: "signed-installer-first-launch")
        app.buttons["Next"].click()
        XCTAssertTrue(app.buttons["Edit weekly schedule"].waitForExistence(timeout: 8))
        attachScreenshot(of: app, named: "signed-installer-schedule-setup")
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        app.buttons["I've reviewed these seven days — use this weekly schedule"].click()
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        app.buttons["Next"].click()
        XCTAssertTrue(app.staticTexts["Step 3 of 5"].waitForExistence(timeout: 5))
        app.buttons["Next"].click()
        XCTAssertTrue(app.staticTexts["Accessibility access required"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        XCTAssertTrue(app.buttons["Open System Settings"].exists)
        XCTAssertTrue(app.buttons["Not now"].isEnabled)
        attachScreenshot(of: app, named: "signed-installer-permission-gate")
        let receiptPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["CURFEW_SIGNED_INSTALLER_RECEIPT"]
        )
        let receipt: [String: Any] = try [
            "version": XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")),
            "bundleIdentifier": XCTUnwrap(bundle.bundleIdentifier),
            "welcomeVisible": true,
            "scheduleSetupVisible": true,
            "scheduleChoiceRequired": true,
            "accessibilityPermissionRequired": true,
            "scope": "Installer trust, setup choices and permission gate only"
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: receiptPath), options: .atomic)
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
