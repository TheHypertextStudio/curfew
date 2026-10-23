import AppKit
import Darwin
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
    func testSignedStagingUpgrade() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CURFEW_SIGNED_UPGRADE_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        try requireDisposableUpgradeRunner(environment)
        let expectedVersion = try XCTUnwrap(environment["CURFEW_SIGNED_UPGRADE_VERSION"])
        XCTAssertEqual(expectedVersion, "0.0.11")
        XCTAssertEqual(installedVersion(), "0.0.8")
        let app = XCUIApplication(bundleIdentifier: "studio.hypertext.apps.curfew")
        app.launch()
        defer { app.terminate() }
        let appMenu = app.menuBars.menuBarItems["Curfew"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 15))
        let baselinePID = try XCTUnwrap(runningPID())
        appMenu.click()
        let check = appMenu.menuItems["Check for Updates…"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        XCTAssertTrue(check.isEnabled)
        check.click()
        let install = app.buttons["Install Update"]
        XCTAssertTrue(install.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", expectedVersion
        )).firstMatch.exists)
        attachScreenshot(of: app, named: "signed-staging-update-offered")
        install.click()
        let relaunch = app.buttons["SUStatusInstallAndRelaunch"]
        XCTAssertTrue(relaunch.waitForExistence(timeout: 60))
        XCTAssertTrue(relaunch.isEnabled)
        attachScreenshot(of: app, named: "signed-staging-update-ready")
        relaunch.click()

        // Do not launch or activate here: Sparkle itself must replace and relaunch.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if installedVersion() == expectedVersion,
               let currentPID = runningPID(), currentPID != baselinePID,
               app.state == .runningForeground || app.state == .runningBackground {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(installedVersion(), expectedVersion)
        let relaunchedPID = try XCTUnwrap(runningPID())
        XCTAssertNotEqual(relaunchedPID, baselinePID)
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        attachScreenshot(of: app, named: "signed-staging-update-relaunched")
        try writeUpgradeReceipt(
            environment: environment,
            version: expectedVersion,
            baselinePID: baselinePID,
            relaunchedPID: relaunchedPID
        )
    }

    private func requireDisposableUpgradeRunner(_ environment: [String: String]) throws {
        let account = try XCTUnwrap(getpwuid(geteuid()))
        try XCTSkipUnless(
            environment["GITHUB_ACTIONS"] == "true"
                && String(cString: account.pointee.pw_name) == "runner"
                && String(cString: account.pointee.pw_dir) == "/Users/runner"
                && environment["RUNNER_TEMP"] == "/Users/runner/work/_temp",
            "Signed updater acceptance requires the real disposable hosted user"
        )
    }

    private func installedVersion() -> String? {
        let infoURL = URL(fileURLWithPath: "/Applications/Curfew.app/Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
              as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    private func runningPID() -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "studio.hypertext.apps.curfew")
            .first { $0.bundleURL?.path == "/Applications/Curfew.app" }?.processIdentifier
    }

    private func writeUpgradeReceipt(
        environment: [String: String],
        version: String,
        baselinePID: pid_t,
        relaunchedPID: pid_t
    ) throws {
        let receipt: [String: Any] = [
            "baselineVersion": "0.0.8", "version": version,
            "bundleIdentifier": "studio.hypertext.apps.curfew",
            "baselinePID": baselinePID, "relaunchedPID": relaunchedPID,
            "sparkleInstallAndRelaunch": true,
            "scope": "Signed Sparkle upgrade only; owner data/helper continuity remains separate"
        ]
        let path = try XCTUnwrap(environment["CURFEW_SIGNED_UPGRADE_RECEIPT"])
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
