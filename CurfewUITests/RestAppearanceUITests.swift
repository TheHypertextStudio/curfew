import XCTest

@MainActor
extension CurfewUITests {
    func testRestScreenSettingsStartWithSafeLocalDefaults() throws {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-restScreen-tab"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()

        XCTAssertTrue(app.descendants(matching: .any)["rest-appearance-preview"]
            .waitForExistence(timeout: 5))
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Rest Screen settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let output = repository.appendingPathComponent("build/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: output.appendingPathComponent(
            "curfew-rest-settings.png"
        ))
        XCTAssertTrue(app.popUpButtons["rest-background-choice"].exists)
        XCTAssertTrue(app.popUpButtons["rest-palette-choice"].exists)
        XCTAssertTrue(app.popUpButtons["rest-clock-style"].exists)
        XCTAssertTrue(app.popUpButtons["rest-clock-position"].exists)
        XCTAssertTrue(app.textFields["rest-personal-message"].exists)
        let detail = app.descendants(matching: .any)["settings-detail"]
        let sharing = app.switches["rest-saver-message"]
        assertOff(sharing, revealingIn: detail)
        let sunrise = app.switches["rest-sunrise-wake"]
        assertOff(sunrise, revealingIn: detail)
        let battery = app.switches["rest-sunrise-battery"]
        assertOff(battery, revealingIn: detail)
        try app.screenshot().pngRepresentation.write(to: output.appendingPathComponent(
            "curfew-rest-settings-sunrise.png"
        ))
    }

    func testRestScreenShowsWakeRequestStatus() {
        let app = launchFixture("settings", state: "ready")
        let destination = app.descendants(matching: .any)["settings-restScreen-tab"]
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.click()
        let detail = app.descendants(matching: .any)["settings-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let status = app.descendants(matching: .any)["rest-sunrise-status"]
        XCTAssertTrue(
            status.waitForExistence(timeout: 3),
            "Sunrise must report its request status separately from the opt-in control."
        )
        for _ in 0 ..< 6 where !status.isHittable {
            detail.scroll(byDeltaX: 0, deltaY: -250)
        }
        XCTAssertTrue(status.isHittable)
        XCTAssertEqual(status.label, "Sunrise is off.")
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
