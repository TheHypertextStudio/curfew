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
        let sunrise = app.switches["rest-sunrise-wake"]
        XCTAssertTrue(sunrise.exists)
        XCTAssertEqual(sunrise.value as? String, "0")
        let battery = app.switches["rest-sunrise-battery"]
        XCTAssertTrue(battery.exists)
        XCTAssertEqual(battery.value as? String, "0")
        let sharing = app.switches["rest-saver-message"]
        XCTAssertTrue(sharing.exists)
        XCTAssertEqual(sharing.value as? String, "0")
    }
}
