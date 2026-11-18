import XCTest

/// Opens the real status-item popover; never substitutes a workspace or desktop image.
@MainActor
private enum MenuBarCapture {
    static func open(_ app: XCUIApplication) -> XCUIElement {
        let identified = app.descendants(matching: .any)
            .matching(identifier: "curfew-status-item").firstMatch
        let labeled = app.menuBars.menuBarItems.matching(NSPredicate(
            format: "label ENDSWITH %@", " status"
        )).firstMatch
        let item = identified.waitForExistence(timeout: 5) ? identified : labeled
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.click()
        let popover = app.descendants(matching: .any)
            .matching(identifier: "curfew-menu-popover").firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5), app.debugDescription)
        // ContentView.width: the popover's square 340-point sky.
        XCTAssertEqual(popover.frame.width, 340, accuracy: 2)
        XCTAssertGreaterThan(popover.frame.height, 150)
        XCTAssertTrue(popover.buttons["Open Curfew"].exists)
        XCTAssertTrue(popover.buttons["Settings"].exists)
        return popover
    }

    /// With Curfew off, the popover says so, offers to turn it back on, and
    /// offers no more time: there is no curfew to extend.
    static func assertOffWithoutMoreTime(
        _ popover: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let off = "Curfew is off."
        XCTAssertTrue(popover.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ OR value BEGINSWITH %@", off, off
        )).firstMatch.exists, file: file, line: line)
        XCTAssertTrue(popover.buttons["Turn on Curfew"].exists, file: file, line: line)
        XCTAssertFalse(popover.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "more minute", "extension"
        )).firstMatch.exists, file: file, line: line)
    }
}

@MainActor
extension CurfewUITests {
    func testMenuBarPopoverOpensActualView() {
        let app = launchFixture("menu-bar", state: "ready")
        let popover = MenuBarCapture.open(app)
        XCTAssertFalse(popover.buttons["Finish Setup"].exists)
    }

    func testOffMenuDoesNotOfferAnExtensionDuringScheduledWarning() {
        let app = launchFixture("menu-bar", state: "menu-off-warning")
        let popover = MenuBarCapture.open(app)
        MenuBarCapture.assertOffWithoutMoreTime(popover)
        XCTAssertFalse(popover.buttons["Call it a day"].exists)
    }
}

@MainActor
extension MarketingCaptureTests {
    func testCaptureMenuBar() {
        for appearance in ["light", "dark"] {
            for state in [
                "ready", "accessibility-denied", "tap-down", "helper-unauthorized",
                "menu-off-warning"
            ] {
                let app = launch("menu-bar", state: state, appearance: appearance)
                let popover = MenuBarCapture.open(app)
                switch state {
                case "menu-off-warning":
                    MenuBarCapture.assertOffWithoutMoreTime(popover)
                case "accessibility-denied":
                    XCTAssertTrue(popover.staticTexts[
                        "Accessibility access needed to block shortcuts during lockout."
                    ].exists)
                    XCTAssertTrue(popover.buttons["Restore blocking"].exists)
                case "tap-down":
                    XCTAssertTrue(popover.staticTexts[
                        "Keyboard shortcut blocking was interrupted. "
                            + "Choose Restore shortcut blocking to retry."
                    ].exists)
                    XCTAssertTrue(popover.buttons["Restore blocking"].exists)
                case "helper-unauthorized":
                    XCTAssertTrue(popover.staticTexts[
                        "The Curfew helper can't verify Curfew. "
                            + "Reinstall it from the official website."
                    ].exists)
                    XCTAssertFalse(popover.buttons["Restore blocking"].exists)
                    XCTAssertTrue(popover.buttons["Open settings"].exists)
                default:
                    XCTAssertFalse(popover.buttons["Restore blocking"].exists)
                }
                attach(popover, name: "menu-bar-\(state)-\(appearance)")
                app.terminate()
            }
        }
    }
}
