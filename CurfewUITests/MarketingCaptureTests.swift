import XCTest

/// Captures only an asserted fixture window or an asserted full-screen overlay.
/// No missing-window fallback: a desktop capture is never a passing result.
final class MarketingCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureSettingsMatrix() {
        for appearance in ["light", "dark"] {
            for size in ["default", "minimum"] {
                let app = launch("settings", appearance: appearance, size: size)
                let window = app.windows["com_apple_SwiftUI_Settings_window"]
                XCTAssertTrue(window.waitForExistence(timeout: 8))
                for section in [
                    "general",
                    "enforcement",
                    "warnings",
                    "integrations",
                    "advanced",
                    "about"
                ] {
                    app.descendants(matching: .any)["settings-\(section)-tab"].click()
                    XCTAssertTrue(app.scrollViews["settings-detail"].waitForExistence(timeout: 3))
                    let titles = [
                        "general": "Protection",
                        "enforcement": "Weekly allowance",
                        "warnings": "Before lockout",
                        "integrations": "AI assistants",
                        "advanced": "Remove Curfew",
                        "about": "Curfew Plus"
                    ]
                    assertText(titles[section] ?? section, in: app)
                    if section == "integrations" {
                        assertText("Curfew Account", in: app)
                        XCTAssertTrue(window.staticTexts["Curfew Account"].exists)
                    }
                    attach(window, name: "settings-\(section)-\(appearance)-\(size)")
                    scrollToBottom(window)
                    attach(window, name: "settings-\(section)-bottom-\(appearance)-\(size)")
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testCaptureCriticalStateMatrix() {
        for appearance in ["light", "dark"] {
            for size in ["default", "minimum"] {
                for state in [
                    "accessibility-denied",
                    "helper-unauthorized",
                    "assistant-on",
                    "license-invalid"
                ] {
                    let app = launch("settings", state: state, appearance: appearance, size: size)
                    let window = app.windows["com_apple_SwiftUI_Settings_window"]
                    XCTAssertTrue(window.waitForExistence(timeout: 8))
                    assertSettingsState(state, in: app)
                    if state == "assistant-on" {
                        app.buttons["manual-assistant-setup"].click()
                        XCTAssertTrue(app.buttons["copy-assistant-config"]
                            .waitForExistence(timeout: 3))
                    }
                    attach(window, name: "critical-\(state)-\(appearance)-\(size)")
                    app.terminate()
                }
                let app = launch("settings", appearance: appearance, size: size)
                app.descendants(matching: .any)["settings-advanced-tab"].click()
                app.buttons["Uninstall Curfew…"].click()
                let alert = app.dialogs.firstMatch
                XCTAssertTrue(alert.waitForExistence(timeout: 5))
                assertText("This cannot be undone.", in: app)
                XCTAssertTrue(alert.buttons["Uninstall"].exists)
                XCTAssertTrue(alert.buttons["Cancel"].exists)
                XCTAssertGreaterThan(alert.frame.width, 220)
                attach(alert.screenshot(), name: "uninstall-confirm-\(appearance)-\(size)")
                alert.buttons["Cancel"].click()
                app.terminate()
            }
        }
    }

    @MainActor
    func testCaptureWorkspaceMatrix() {
        for appearance in ["light", "dark"] {
            for size in ["default", "minimum"] {
                for scenario in ["overview", "configuration", "this-week", "getting-started"] {
                    let app = launch(scenario, appearance: appearance, size: size)
                    let prefix = scenario == "getting-started"
                        ? "getting-started" : "main-workspace"
                    let window = app.windows.matching(NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        prefix
                    )).firstMatch
                    XCTAssertTrue(window.waitForExistence(timeout: 8))
                    attach(window, name: "\(scenario)-\(appearance)-\(size)")
                    if ["configuration", "this-week"].contains(scenario) {
                        scrollToBottom(window)
                        attach(window, name: "\(scenario)-bottom-\(appearance)-\(size)")
                    }
                    if scenario == "getting-started" {
                        for step in 1 ... 4 {
                            if step == 2 {
                                app.buttons["Open Schedule"].click()
                                app.typeKey("w", modifierFlags: .command)
                            }
                            app.buttons["Next"].click()
                            assertText("Step \(step + 1) of 5", in: app)
                            attach(window, name: "setup-step-\(step + 1)-\(appearance)-\(size)")
                        }
                    }
                    if scenario == "this-week" {
                        app.radioButtons["Prompts"].click()
                        XCTAssertTrue(app.staticTexts["Your reflections and AI"]
                            .waitForExistence(timeout: 3))
                        attach(window, name: "prompts-\(appearance)-\(size)")
                        scrollToBottom(window)
                        attach(window, name: "prompts-bottom-\(appearance)-\(size)")
                    }
                    app.terminate()
                }
            }
        }
    }

    @MainActor
    func testCaptureDistinctSettingsStates() {
        let states = [
            "ready",
            "accessibility-denied",
            "tap-down",
            "helper-approval",
            "helper-unauthorized",
            "helper-stale",
            "helper-registration",
            "login-approval",
            "limits-none",
            "assistant-on",
            "assistant-read-only",
            "assistant-automatic",
            "assistant-pending",
            "claude-absent",
            "claude-configured",
            "license-invalid",
            "license-lifetime",
            "license-subscription",
            "license-expired",
            "cloud-idle",
            "cloud-syncing",
            "cloud-synced",
            "cloud-failed",
            "cloud-unavailable",
            "calendar-denied",
            "calendar-empty"
        ]
        for state in states {
            let app = launch("settings", state: state)
            let window = app.windows["com_apple_SwiftUI_Settings_window"]
            XCTAssertTrue(window.waitForExistence(timeout: 8))
            assertSettingsState(state, in: app)
            attach(window, name: "state-\(state)")
            if state.hasPrefix("assistant-") || state.hasPrefix("claude-")
                || state.hasPrefix("cloud-") || state.hasPrefix("calendar-") {
                scrollToBottom(window)
                attach(window, name: "state-\(state)-details")
            }
            if state == "assistant-pending" {
                app.buttons["review-ai-request"].click()
                XCTAssertTrue(app.buttons["Approve"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Deny"].exists)
                let sheet = app.sheets.firstMatch
                XCTAssertTrue(sheet.waitForExistence(timeout: 3))
                attach(sheet, name: "pending-ai-request")
            }
            app.terminate()
        }
    }

    @MainActor
    func testCaptureDistinctWorkspaceStates() {
        for (scenario, states) in [
            ("configuration", ["schedule-pending", "schedule-applied", "schedule-overnight"]),
            ("overview", ["day-off", "accessibility-denied"]),
            ("this-week", ["journal-populated", "prompts-empty"]),
            (
                "lockout",
                [
                    "override-cooldown",
                    "override-invalid",
                    "override-ready",
                    "overrides-exhausted",
                    "shutdown-denied",
                    "shutdown-failed"
                ]
            )
        ] {
            for state in states {
                let app = launch(scenario, state: state)
                if scenario == "lockout" {
                    let overlay = app.descendants(matching: .any)["lockout-screen"]
                    XCTAssertTrue(overlay.waitForExistence(timeout: 8))
                    assertWorkspaceState(state, in: app)
                    attach(overlay, name: "state-\(state)")
                } else {
                    let window = app.windows.matching(NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        "main-workspace"
                    )).firstMatch
                    XCTAssertTrue(window.waitForExistence(timeout: 8))
                    if state == "prompts-empty" {
                        app.radioButtons["Prompts"].click()
                    }
                    assertWorkspaceState(state, in: app)
                    attach(window, name: "state-\(state)")
                    if state == "journal-populated" {
                        scrollToBottom(window)
                        attach(window, name: "state-journal-populated-bottom")
                    }
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testCaptureOverlays() {
        for appearance in ["light", "dark"] {
            var app = launch("warning", appearance: appearance)
            XCTAssertTrue(app.staticTexts["warning-countdown"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["warning-countdown"].value as? String, "2 min")
            let warning = app.descendants(matching: .any)["warning-timer"]
            XCTAssertTrue(warning.waitForExistence(timeout: 3))
            XCTAssertGreaterThan(warning.frame.width, 80)
            XCTAssertLessThan(warning.frame.height, 80)
            attach(warning.screenshot(), name: "warning-\(appearance)")
            app.terminate()
            app = launch("lockout", appearance: appearance)
            let overlay = app.descendants(matching: .any)["lockout-screen"]
            XCTAssertTrue(overlay.waitForExistence(timeout: 8))
            attach(overlay, name: "lockout-\(appearance)")
            app.terminate()
        }
    }
}

extension MarketingCaptureTests {
    @MainActor
    func testCaptureOverrideContrast() {
        for appearance in ["light", "dark"] {
            for state in ["override-invalid", "override-ready"] {
                let app = launch("lockout", state: state, appearance: appearance)
                let overlay = app.descendants(matching: .any)["lockout-screen"]
                XCTAssertTrue(overlay.waitForExistence(timeout: 8))
                assertWorkspaceState(state, in: app)
                attach(overlay, name: "override-\(state)-\(appearance)")
                app.terminate()
            }
        }
    }

    @MainActor
    private func launch(
        _ scenario: String,
        state: String = "default",
        appearance: String = "light",
        size: String = "default"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CURFEW_DEMO_FIXTURE": "1",
            "CURFEW_DEMO_SCENARIO": scenario,
            "CURFEW_DEMO_STATE": state,
            "CURFEW_DEMO_APPEARANCE": appearance,
            "CURFEW_DEMO_SIZE": size
        ]
        app.launchArguments = ["-SUEnableAutomaticChecks", "NO", "-SUHasLaunchedBefore", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        if scenario == "settings" {
            app.typeKey(",", modifierFlags: .command)
        }
        return app
    }

    @MainActor
    private func scrollToBottom(_ window: XCUIElement) {
        let detail = window.scrollViews["settings-detail"]
        guard let pane = detail.exists ? detail : window.scrollViews.allElementsBoundByIndex
            .max(by: {
                $0.frame.width < $1.frame.width
            }) else {
            XCTFail("A bottom capture requires a content pane")
            return
        }
        XCTAssertTrue(pane.exists, "A bottom capture requires a scrollable content pane")
        pane.scroll(byDeltaX: 0, deltaY: 10000)
        func bottomOfContent() -> CGFloat {
            let content = pane.staticTexts.allElementsBoundByIndex
                + pane.buttons.allElementsBoundByIndex
                + pane.textFields.allElementsBoundByIndex
                + pane.popUpButtons.allElementsBoundByIndex
            return content.map(\.frame.maxY).max() ?? pane.frame.maxY
        }
        if bottomOfContent() > pane.frame.maxY + 2 {
            // Wheel direction differs between native panes. Verify the result
            // rather than assuming the first scroll reached the lower controls.
            pane.scroll(byDeltaX: 0, deltaY: -10000)
        }
        let contentFits = bottomOfContent() <= pane.frame.maxY + 2
        let bars = pane.scrollBars.allElementsBoundByIndex.filter {
            $0.frame.height > $0.frame.width
        }
        if let bar = bars.first {
            let value = Double(String(describing: bar.value ?? ""))
            XCTAssertNotNil(value, "The vertical scroll position must be readable")
            XCTAssertTrue(
                (value ?? 0) >= 0.99 || contentFits,
                "Capture must reach the bottom or show all lower content"
            )
        } else {
            XCTAssertTrue(contentFits, "Without a scroll bar, all lower content must fit")
        }
    }

    @MainActor
    private func attach(_ element: XCUIElement, name: String) {
        XCTAssertTrue(element.exists)
        XCTAssertGreaterThan(element.frame.width, 300)
        XCTAssertGreaterThan(element.frame.height, 100)
        attach(element.screenshot(), name: name)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "curfew-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
