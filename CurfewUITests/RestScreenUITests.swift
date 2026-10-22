import XCTest

extension CurfewUITests {
    @MainActor
    func testIsolatedUnlockLabelHasReadableAccessibleText() throws {
        let app = launchFixture("lockout", state: "rest-contrast-control")
        defer { app.terminate() }
        let label = app.staticTexts.firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts.count,
            1,
            "The control must contain only the actual unlock label."
        )
        XCTAssertFalse(app.textViews["reflection-answer"].exists)
        let text = label.value as? String ?? label.label
        XCTAssertTrue(text.hasPrefix("Your computer unlocks at "))
        XCTAssertEqual(app.groups["rest-screen"].label, "Curfew rest screen")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Isolated formatted unlock label"
        capture.lifetime = .keepAlways
        add(capture)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription])
    }

    @MainActor
    func testReflectionTypingSurvivesClockTicks() {
        let app = launchFixture("lockout", state: "rest-continuity")
        let editor = app.textViews["reflection-answer"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("I finished the important work and made time for a walk.")
        let expected = editor.value as? String
        sleep(3)
        XCTAssertEqual(editor.value as? String, expected)
        editor.typeText(" Tomorrow can wait.")
        XCTAssertTrue((editor.value as? String)?.hasSuffix("Tomorrow can wait.") == true)
    }

    @MainActor
    func testResolvingReflectionMakesRoomForTheQuietClock() {
        let app = launchFixture("lockout", state: "rest-continuity")
        let clock = app.staticTexts["rest-clock"]
        let editor = app.textViews["reflection-answer"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let editingHeight = clock.frame.height
        XCTAssertGreaterThan(editingHeight, 0)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Rest — editing"
        before.lifetime = .keepAlways
        add(before)
        app.buttons["Skip"].click()
        sleep(2)
        XCTAssertFalse(editor.exists)
        XCTAssertGreaterThan(clock.frame.height, editingHeight * 1.3)
        XCTAssertTrue(app.buttons["override-entry"].exists)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Rest — quiet night"
        after.lifetime = .keepAlways
        add(after)
    }

    @MainActor
    func testRestScenesHaveReadableAccessibleControls() throws {
        for state in ["rest-continuity", "rest-morning"] {
            let app = launchFixture("lockout", state: state)
            let editor = app.textViews["reflection-answer"].firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertFalse(editor.label.isEmpty)
            XCTAssertEqual(app.groups["rest-screen"].label, "Curfew rest screen")
            try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription])
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
    }

    @MainActor
    func testOverrideHoldSurvivesClockTicks() {
        let app = launchFixture("lockout", state: "rest-hold")
        let hold = app.buttons["override-hold-confirm"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssertTrue(hold.isEnabled)
        hold.press(forDuration: 1)
        XCTAssertTrue(hold.exists, "A short hold must not authorize release.")
        hold.press(forDuration: 3.3)
        XCTAssertTrue(
            hold.waitForNonExistence(timeout: 5),
            "A complete hold must survive clock updates."
        )
    }
}
