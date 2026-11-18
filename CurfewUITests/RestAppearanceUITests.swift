import XCTest

@MainActor
extension CurfewUITests {
    func testRestScreenSettingsStartWithSafeLocalDefaults() {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-category-restScreen"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()

        XCTAssertTrue(app.descendants(matching: .any)["rest-appearance-preview"]
            .waitForExistence(timeout: 5))
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "curfew-rest-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent("build/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: output.appendingPathComponent(
            "curfew-rest-settings.png"
        ))
        XCTAssertTrue(app.popUpButtons["rest-background-choice"].exists)
        let controls = ["sundown", "warmAmber", "coolTwilight"].map { "rest-palette-\($0)" }
            + ["rounded", "standard", "serif"].map { "rest-clock-style-\($0)" }
            + ["default", "gentle", "playful"].map { "rest-voice-\($0)" }
            + ["rest-clock-position", "rest-own-words"]
        for identifier in controls {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].exists, identifier)
        }
        // No line is in the person's own words yet, so the screen saver is offered none:
        // its consent checkbox appears only beside a rewritten lock line.
        XCTAssertTrue(app.staticTexts["Rewrite the lines that carry the voice."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["rest-saver-message"].exists)
    }

    func testSunriseSettingsStartWithWakeOff() {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-category-sunrise"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()
        let detail = app.descendants(matching: .any)["settings-page-sunrise"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertOff(app.switches["sunrise-wake"], revealingIn: detail)
        // "Allow on battery" appears only on a Mac with a battery.
        let battery = app.switches["sunrise-battery"]
        if battery.exists {
            assertOff(battery, revealingIn: detail)
        }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "curfew-sunrise-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Do not enable wake or launch system services in this disarmed UI contract.
    }

    private func assertOff(
        _ control: XCUIElement, revealingIn detail: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(control.exists, file: file, line: line)
        for _ in 0 ..< 6 where !control.isHittable {
            detail.scroll(byDeltaX: 0, deltaY: -250)
        }
        XCTAssertTrue(control.isHittable, file: file, line: line)
        let value = control.value
        let off = (value as? String) == "0" || (value as? NSNumber)?.doubleValue == 0
        XCTAssertTrue(
            off,
            "Expected an off switch, got \(String(reflecting: value)); \(control.debugDescription)",
            file: file, line: line
        )
    }
}
