import XCTest

final class CurfewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingStartsAtARealGate() {
        let app = launchFixture("getting-started")

        XCTAssertTrue(app.staticTexts["Welcome to Curfew"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)
        XCTAssertFalse(app.buttons["Back"].isEnabled)
        XCTAssertTrue(app.buttons["Next"].isEnabled)
        XCTAssertTrue(app.buttons["Not now"].exists)
    }

    @MainActor
    func testWarningAndLockoutPresentation() {
        var app = launchFixture("warning")
        XCTAssertTrue(app.staticTexts["warning-countdown"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["warning-countdown"].value as? String, "2 min")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))

        app = launchFixture("lockout")
        XCTAssertTrue(app.descendants(matching: .any)["lockout-screen"]
            .waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["override-entry"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOverrideRequiresCooldownReasonAndHold() {
        let app = launchFixture("lockout")
        let entry = app.buttons["override-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()

        XCTAssertTrue(app.textViews["override-reason"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["override-cooldown"].exists)
        XCTAssertTrue(app.staticTexts["Minimum 50 characters"].exists)
        let hold = app.buttons["override-hold-confirm"]
        XCTAssertTrue(hold.exists)
        XCTAssertFalse(hold.isEnabled, "Hold confirmation must stay disabled during cooldown.")
    }

    @MainActor
    func testShippingIntegrationsAndHelperFailureAreVisible() {
        let app = launchFixture("settings")
        let integrations = app.descendants(matching: .any)["settings-integrations-tab"]
        XCTAssertTrue(integrations.waitForExistence(timeout: 8))
        integrations.tap()

        XCTAssertTrue(app.staticTexts["Widgets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Calendar"].exists)
        XCTAssertFalse(app.staticTexts["iCloud sync"].exists)
        app.descendants(matching: .any)["settings-general-tab"].click()
        XCTAssertTrue(app.staticTexts["Background protection"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.disclosureTriangles["Troubleshooting"].exists)
    }

    @MainActor
    func testSettingsUsesSidebarAndShowsOnlyRelevantControls() {
        let app = launchFixture("settings")
        let general = app.descendants(matching: .any)["settings-general-tab"]
        XCTAssertTrue(general.waitForExistence(timeout: 8))
        let limits = app.descendants(matching: .any)["settings-enforcement-tab"]
        limits.click()
        XCTAssertTrue(app.staticTexts["Weekly allowance"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["settings-integrations-tab"].click()
        XCTAssertTrue(app.staticTexts["AI assistants"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["MCP Control Plane"].exists)
        XCTAssertFalse(app.staticTexts["Additional Integrations"].exists)
        app.descendants(matching: .any)["settings-about-tab"].click()
        XCTAssertFalse(app.staticTexts["iCloud sync across all your Macs"].exists)
        XCTAssertFalse(app.staticTexts["Calendar-aware schedule exceptions"].exists)
    }

    @MainActor
    func testGeneralKeepsNavigationAndSetupInView() {
        let app = launchFixture("settings", state: "ready")
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let general = app.descendants(matching: .any)["settings-general-tab"]
        XCTAssertLessThan(general.frame.minY - window.frame.minY, 95)
        let review = app.buttons["Review Setup…"]
        XCTAssertTrue(review.exists)
        XCTAssertLessThan(review.frame.maxY, window.frame.maxY - 12)
        XCTAssertFalse(app.staticTexts["Initial setup"].exists)
        XCTAssertFalse(app.staticTexts["Installation"].exists)
    }

    @MainActor
    func testGeneralPermissionFailureFitsMinimumWindow() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CURFEW_DEMO_FIXTURE": "1", "CURFEW_DEMO_SCENARIO": "settings",
            "CURFEW_DEMO_STATE": "accessibility-denied", "CURFEW_DEMO_SIZE": "minimum"
        ]
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Accessibility Settings"].exists)
        XCTAssertLessThan(app.buttons["Review Setup…"].frame.maxY, window.frame.maxY - 12)
    }

    @MainActor
    func testOffStateDoesNotPromiseAnActiveLock() {
        let app = launchFixture("overview")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Scheduled lock",
            "Scheduled lock"
        ))
        .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@",
            "until your Mac locks"
        ))
        .firstMatch.exists)
    }

    @MainActor
    func testSetupUsesOneInstructionAndPreservesScheduleGate() {
        let app = launchFixture("getting-started")
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].click()
        XCTAssertTrue(app.staticTexts["Choose when your Mac locks and unlocks."]
            .waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Next"].isEnabled)
        XCTAssertTrue(app.buttons["Open Schedule"].exists)
    }

    @MainActor
    func testPromptEditorDoesNotAdvertiseFutureFeatures() {
        let app = launchFixture("this-week")
        app.radioButtons["Prompts"].click()
        XCTAssertTrue(app.staticTexts["Your reflections and AI"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@",
            "coming"
        ))
        .firstMatch.exists)
    }

    @MainActor
    func testAssistantSetupShowsCopyFeedback() {
        let app = launchFixture("settings")
        app.descendants(matching: .any)["settings-integrations-tab"].click()
        let toggle = app.descendants(matching: .any)["assistant-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(app.popUpButtons["assistant-policy"].waitForExistence(timeout: 3))
        app.buttons["manual-assistant-setup"].click()
        let copy = app.buttons["copy-assistant-config"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        copy.click()
        XCTAssertEqual(copy.label, "Copied")
    }

    @MainActor
    func testReadyFixtureDoesNotImplyCurfewIsOn() {
        let app = launchFixture("settings", state: "ready")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "Ready to enforce",
            "Ready to enforce"
        ))
        .firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@",
            "Enforcement is active"
        ))
        .firstMatch.exists)
    }

    @MainActor
    func testScheduleHidesTimeControlsForDaysOff() {
        let app = launchFixture("configuration")
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.datePickers.count, 10)
    }

    @MainActor
    func testSparkleUpdateCommandIsPresent() {
        let app = launchFixture("overview")
        let appMenu = app.menuBars.menuBarItems["Curfew"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 8))
        appMenu.click()
        XCTAssertTrue(app.menuItems["Check for Updates…"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMinimumSettingsWindowRetainsAllConsentChoices() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CURFEW_DEMO_FIXTURE": "1",
            "CURFEW_DEMO_SCENARIO": "settings",
            "CURFEW_DEMO_STATE": "assistant-on",
            "CURFEW_DEMO_SIZE": "minimum"
        ]
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, 760, accuracy: 2)
        XCTAssertTrue(app.popUpButtons["assistant-policy"].exists)
    }

    @MainActor
    func testReviewOpensPendingRequestAndDenyDismissesIt() {
        let app = launchFixture("settings", state: "assistant-pending")
        let review = app.buttons["review-ai-request"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.click()
        XCTAssertTrue(app.buttons["Approve"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Deny"].exists)
        let workspaces = app.windows.matching(NSPredicate(
            format: "identifier BEGINSWITH %@",
            "main-workspace"
        ))
        XCTAssertEqual(workspaces.count, 1)
        app.buttons["Deny"].click()
        XCTAssertFalse(app.buttons["Approve"].exists)
    }

    @MainActor
    func testExhaustedOverridesExplainWhyEntryIsUnavailable() {
        let app = launchFixture("lockout", state: "overrides-exhausted")
        XCTAssertTrue(app.staticTexts["No overrides left this week"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["override-entry"].exists)
    }

    @MainActor
    func launchFixture(_ scenario: String, state: String = "default") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = scenario
        app.launchEnvironment["CURFEW_DEMO_STATE"] = state
        app.launchArguments += ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        if app.state != .runningForeground {
            app.activate()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if scenario == "settings" {
            app.typeKey(",", modifierFlags: .command)
        }
        return app
    }
}

extension CurfewUITests {
    @MainActor
    func testTaskBrowserEnforcementPanelActions() {
        let app = launchFixture("settings")
        app.descendants(matching: .any)["settings-integrations-tab"].click()
        let destinations = app.buttons["task-browser-destinations-disclosure"]
        XCTAssertTrue(destinations.waitForExistence(timeout: 5), app.debugDescription)
        destinations.click()
        XCTAssertTrue(
            app.buttons["Remove instagram.com"].waitForExistence(timeout: 3),
            "Expanded destinations must expose their remove action.\n\(app.debugDescription)"
        )

        XCTAssertTrue(app.staticTexts["Websites during work"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Complete LVBT social strategy"].exists)
        XCTAssertTrue(app.staticTexts["instagram.com"].exists)

        let enforcementToggle = app.switches["task-browser-enforcement-toggle"]
        XCTAssertTrue(enforcementToggle.isEnabled)

        let breakButton = app.buttons["task-browser-break-button"]
        XCTAssertTrue(breakButton.isEnabled)
        breakButton.click()
        XCTAssertTrue(app.staticTexts["Break ends"].waitForExistence(timeout: 2))

        let removeButton = app.buttons["Remove instagram.com"]
        XCTAssertTrue(removeButton.exists)
        removeButton.click()
        XCTAssertFalse(app.staticTexts["instagram.com"].exists)
    }

    @MainActor
    func testAssistantReadAccessIsExplainedBeforeEnabling() {
        let app = launchFixture("settings", state: "ready")
        app.descendants(matching: .any)["settings-integrations-tab"].click()
        XCTAssertTrue(app.staticTexts[
            "Connected assistants can read your status, schedule, activity, and reflections."
        ].waitForExistence(timeout: 3))
        XCTAssertFalse(app.popUpButtons["assistant-policy"].exists)
    }

    @MainActor
    func testGeneralHelperFailureFitsMinimumWindow() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CURFEW_DEMO_FIXTURE": "1", "CURFEW_DEMO_SCENARIO": "settings",
            "CURFEW_DEMO_SIZE": "minimum"
        ]
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let review = app.buttons["Review Setup…"]
        XCTAssertTrue(review.exists)
        XCTAssertLessThan(review.frame.maxY, window.frame.maxY - 12)
        XCTAssertFalse(app.staticTexts["Background protection needs attention."].exists)
        XCTAssertTrue(app.disclosureTriangles["Troubleshooting"].exists)
    }

    @MainActor
    func testSettingsSidebarSupportsArrowKeys() {
        let app = launchFixture("settings", state: "ready")
        app.descendants(matching: .any)["settings-general-tab"].click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Weekly allowance"].waitForExistence(timeout: 3))
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["Protection"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testManageAIAccessAlwaysOpensConnections() {
        let app = launchFixture("this-week")
        app.radioButtons["Prompts"].click()
        let manage = app.buttons["Manage AI Access…"]
        XCTAssertTrue(manage.waitForExistence(timeout: 3))
        app.scrollViews.allElementsBoundByIndex.max {
            $0.frame.width < $1.frame.width
        }?.scroll(byDeltaX: 0, deltaY: 10000)
        manage.click()
        XCTAssertTrue(app.staticTexts["AI assistants"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["settings-general-tab"].click()
        XCTAssertTrue(app.staticTexts["Protection"].waitForExistence(timeout: 3))
        app.windows["main-workspace"].click()
        manage.click()
        XCTAssertTrue(app.staticTexts["AI assistants"].waitForExistence(timeout: 3))
    }
}
