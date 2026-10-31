import AppKit
import Darwin
import XCTest

/// Observes a prepared disposable account without changing setup or permissions.
final class SignedEnforcementAcceptanceTests: XCTestCase {
    private struct EnforcementEvidence {
        var observations: [String: [String: Any]] = [:]
        var uptime: [String: Double] = [:]
        var confirmationHold: Double = 0
    }

    /// Observes an already prepared disposable account. Never grants permissions,
    /// seeds settings, arms a schedule, or changes time.
    @MainActor
    func testSignedWarningLockoutAndOverride() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["CURFEW_SIGNED_ENFORCEMENT_ACCEPTANCE"] == "1")
        continueAfterFailure = false
        executionTimeAllowance = 15 * 60
        try requireDisposableUpgradeRunner(environment)
        let subject = try requirePreparedEnforcementFixture(environment)
        let app = XCUIApplication(bundleIdentifier: "studio.hypertext.apps.curfew")
        app.launchEnvironment = [:]
        app.launch()
        defer {
            // Do not force-quit a failed lockout. Its bounded natural unlock and
            // disposal of the hosted runner remain available after failure.
            if let status = try? signedEnforcementStatus(),
               status["phase"] as? String == "working" {
                app.terminate()
            }
        }
        let lock = try requireBoundedEnforcementSchedule()
        var evidence = EnforcementEvidence()
        try observeSignedWarning(app, evidence: &evidence)
        let overlay = try observeSignedLockout(app, lock: lock, evidence: &evidence)
        try performSignedOverride(app, overlay: overlay, evidence: &evidence)
        try writeEnforcementReceipt(environment, subject: subject, evidence: evidence)
    }

    private func requirePreparedEnforcementFixture(
        _ environment: [String: String]
    ) throws -> [String: String] {
        let bundle = try XCTUnwrap(Bundle(path: "/Applications/Curfew.app"))
        XCTAssertEqual(bundle.bundleIdentifier, "studio.hypertext.apps.curfew")
        let version = try XCTUnwrap(environment["CURFEW_SIGNED_INSTALLER_VERSION"])
        let source = try XCTUnwrap(environment["CURFEW_SIGNED_ENFORCEMENT_SOURCE_COMMIT"])
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            version
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "CurfewConfigurationCommit") as? String,
            source
        )
        XCTAssertNotEqual(
            bundle.object(forInfoDictionaryKey: "CurfewAcceptanceFixture") as? Bool,
            true
        )
        // Read actual existing consent; never manufacture completed onboarding.
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "studio.hypertext.curfew"))
        let data = try XCTUnwrap(
            preferences.data(forKey: "curfew.settings.v1"),
            "Prepare the disposable account through the real setup UI first"
        )
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(settings["hasCompletedInitialSetup"] as? Bool, true)
        XCTAssertEqual(settings["autoShutdownEnabled"] as? Bool, false)
        XCTAssertTrue(preferences.bool(forKey: "curfew.automaticScheduleConsent.v1"))
        XCTAssertGreaterThan(settings["overrideWeeklyLimit"] as? Int ?? 0, 0)
        return try [
            "version": version, "sourceCommit": source,
            "dmgSHA256": XCTUnwrap(environment["CURFEW_SIGNED_ENFORCEMENT_DMG_SHA256"])
        ]
    }

    private func requireBoundedEnforcementSchedule() throws -> Date {
        let initial = try signedEnforcementStatus()
        XCTAssertTrue(
            ["working", "warning"].contains(initial["phase"] as? String ?? ""),
            "The signed app must report healthy protection, not unknown/degraded"
        )
        XCTAssertNil(initial["unavailable_reason"])
        let lock = try signedEnforcementDate(initial, key: "lock_date")
        let unlock = try signedEnforcementDate(initial, key: "unlock_date")
        XCTAssertGreaterThanOrEqual(lock.timeIntervalSinceNow, 60)
        XCTAssertLessThanOrEqual(lock.timeIntervalSinceNow, 6 * 60)
        XCTAssertGreaterThanOrEqual(unlock.timeIntervalSince(lock), 7 * 60)
        XCTAssertLessThanOrEqual(
            unlock.timeIntervalSinceNow, 20 * 60,
            "Refuse an unbounded or overnight fixture lockout"
        )
        return lock
    }

    @MainActor
    private func observeSignedWarning(
        _ app: XCUIApplication, evidence: inout EnforcementEvidence
    ) throws {
        XCTAssertTrue(app.staticTexts["warning-countdown"].waitForExistence(timeout: 90))
        evidence.observations["warning"] = try signedEnforcementStatus()
        XCTAssertEqual(evidence.observations["warning"]?["phase"] as? String, "warning")
        XCTAssertNil(evidence.observations["warning"]?["unavailable_reason"])
        evidence.uptime["warning"] = ProcessInfo.processInfo.systemUptime
        attachScreenshot(of: app, named: "signed-real-warning")
    }

    @MainActor
    private func observeSignedLockout(
        _ app: XCUIApplication, lock: Date, evidence: inout EnforcementEvidence
    ) throws -> XCUIElement {
        let overlay = app.descendants(matching: .any)["lockout-screen"]
        XCTAssertTrue(overlay.waitForExistence(timeout: max(1, lock.timeIntervalSinceNow + 30)))
        evidence.observations["locked"] = try signedEnforcementStatus()
        XCTAssertEqual(
            evidence.observations["locked"]?["phase"] as? String, "locked",
            "A visible overlay with unknown/degraded protection must fail"
        )
        XCTAssertNil(evidence.observations["locked"]?["unavailable_reason"])
        evidence.uptime["locked"] = ProcessInfo.processInfo.systemUptime
        attachScreenshot(of: app, named: "signed-real-lockout")
        return overlay
    }

    @MainActor
    private func performSignedOverride(
        _ app: XCUIApplication, overlay: XCUIElement, evidence: inout EnforcementEvidence
    ) throws {
        let entry = app.buttons["override-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        evidence.uptime["cooldownStarted"] = ProcessInfo.processInfo.systemUptime
        entry.click()
        let reason = app.textViews["override-reason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        let confirm = app.buttons["override-hold-confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)
        reason.click()
        reason.typeText(
            "Disposable signed acceptance: verify the complete cooldown and deliberate hold "
                + "before restoring this isolated test session."
        )
        XCTAssertFalse(confirm.isEnabled)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: confirm
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 315), .completed)
        evidence.uptime["cooldownReady"] = ProcessInfo.processInfo.systemUptime
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(evidence.uptime["cooldownReady"]) -
                XCTUnwrap(evidence.uptime["cooldownStarted"]), 300
        )
        confirm.press(forDuration: 2.5)
        evidence.observations["afterShortHold"] = try signedEnforcementStatus()
        XCTAssertEqual(evidence.observations["afterShortHold"]?["phase"] as? String, "locked")
        XCTAssertNil(evidence.observations["afterShortHold"]?["unavailable_reason"])
        XCTAssertTrue(overlay.exists)
        evidence.uptime["shortHoldEnded"] = ProcessInfo.processInfo.systemUptime
        let holdStarted = ProcessInfo.processInfo.systemUptime
        confirm.press(forDuration: 3.25)
        evidence.confirmationHold = ProcessInfo.processInfo.systemUptime - holdStarted
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: overlay
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        evidence.observations["afterOverride"] = try signedEnforcementStatus()
        XCTAssertEqual(evidence.observations["afterOverride"]?["phase"] as? String, "working")
        XCTAssertNil(evidence.observations["afterOverride"]?["unavailable_reason"])
        evidence.uptime["overrideGranted"] = ProcessInfo.processInfo.systemUptime
        XCTAssertGreaterThanOrEqual(evidence.confirmationHold, 3)
        attachScreenshot(of: app, named: "signed-real-override-unlocked")
    }

    private func writeEnforcementReceipt(
        _ environment: [String: String], subject: [String: String], evidence: EnforcementEvidence
    ) throws {
        let receipt: [String: Any] = [
            "schemaVersion": 1, "scope": "signed-warning-lockout-override", "subject": subject,
            "bundleIdentifier": "studio.hypertext.apps.curfew",
            "runner": [
                "githubActions": "true",
                "username": "runner",
                "home": "/Users/runner",
                "temporary": "/Users/runner/work/_temp"
            ],
            "observations": evidence.observations, "uptime": evidence.uptime,
            "shortHoldSeconds": 2.5, "confirmationHoldSeconds": evidence.confirmationHold,
            "warningTimerVisible": true, "lockoutVisible": true,
            "confirmationInitiallyDisabled": true, "stillLockedAfterShortHold": true,
            "overlayDismissedAfterOverride": true,
            "sideEffects": [
                "directSettingsWrites": false,
                "permissionGrantPerformed": false,
                "clockChanged": false,
                "demoFixtureUsed": false
            ]
        ]
        let path = try XCTUnwrap(environment["CURFEW_SIGNED_ENFORCEMENT_RECEIPT"])
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func signedEnforcementStatus() throws -> [String: Any] {
        let process = Process()
        process
            .executableURL =
            URL(fileURLWithPath: "/Applications/Curfew.app/Contents/Resources/curfew-ctl")
        process.arguments = ["status", "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func signedEnforcementDate(_ status: [String: Any], key: String) throws -> Date {
        let value = try XCTUnwrap(status[key] as? String)
        return try XCTUnwrap(ISO8601DateFormatter().date(from: value))
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

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
