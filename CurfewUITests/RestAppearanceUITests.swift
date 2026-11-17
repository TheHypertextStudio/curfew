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
        XCTAssertTrue(app.popUpButtons["rest-palette-choice"].exists)
        XCTAssertTrue(app.popUpButtons["rest-clock-style"].exists)
        XCTAssertTrue(app.popUpButtons["rest-clock-position"].exists)
        XCTAssertTrue(app.textFields["rest-personal-message"].exists)
        let detail = app.descendants(matching: .any)["settings-page-restScreen"]
        let sharing = app.switches["rest-saver-message"]
        assertOff(sharing, revealingIn: detail)
    }

    func testSunriseSettingsStartWithWakeOff() {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-category-sunrise"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()
        let detail = app.descendants(matching: .any)["settings-page-sunrise"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertOff(app.switches["Wake this Mac for Sunrise"], revealingIn: detail)
        assertOff(app.switches["Allow on battery"], revealingIn: detail)
        let status = app.staticTexts["Sunrise appears when you first use this Mac in the morning."]
        XCTAssertTrue(
            status.waitForExistence(timeout: 3),
            "Sunrise must report its wake status separately from the opt-in control."
        )
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
