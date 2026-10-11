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
        XCTAssertEqual(popover.frame.width, 320, accuracy: 2)
        XCTAssertGreaterThan(popover.frame.height, 150)
        XCTAssertTrue(popover.buttons["Open Curfew"].exists)
        return popover
    }
}

extension CurfewUITests {
    @MainActor
    func testMenuBarPopoverOpensActualView() {
        let app = launchFixture("menu-bar", state: "ready")
        let popover = MenuBarCapture.open(app)
        XCTAssertTrue(popover.buttons["Review Setup"].exists)
        XCTAssertFalse(popover.buttons["Finish Setup"].exists)
    }

    @MainActor
    func testOffMenuDoesNotOfferAnExtensionDuringScheduledWarning() {
        let app = launchFixture("menu-bar", state: "menu-off-warning")
        let popover = MenuBarCapture.open(app)
        XCTAssertTrue(popover.staticTexts["Curfew is off"].exists)
        XCTAssertFalse(popover.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "extension"
        )).firstMatch.exists)
    }
}

extension MarketingCaptureTests {
    @MainActor
    func testCaptureMenuBar() {
        for appearance in ["light", "dark"] {
            for state in [
                "ready", "accessibility-denied", "tap-down", "helper-unauthorized",
                "menu-off-warning"
            ] {
                let app = launch("menu-bar", state: state, appearance: appearance)
                let popover = MenuBarCapture.open(app)
                XCTAssertTrue(popover.buttons["Review Setup"].exists)
                switch state {
                case "menu-off-warning":
                    XCTAssertTrue(popover.staticTexts["Curfew is off"].exists)
                    XCTAssertFalse(popover.buttons.matching(NSPredicate(
                        format: "label CONTAINS %@", "extension"
                    )).firstMatch.exists)
                case "accessibility-denied":
                    XCTAssertTrue(popover.staticTexts[
                        "Accessibility access needed to block shortcuts during lockout."
                    ].exists)
                    XCTAssertTrue(popover.buttons["Fix Accessibility"].exists)
                case "tap-down":
                    XCTAssertTrue(popover.staticTexts[
                        "Keyboard protection interrupted. Reopen Curfew to restore it."
                    ].exists)
                case "helper-unauthorized":
                    XCTAssertTrue(popover.staticTexts[
                        "Background protection can't verify Curfew. "
                            + "Reinstall Curfew from the official website."
                    ].exists)
                    XCTAssertFalse(popover.buttons["Fix Accessibility"].exists)
                default:
                    XCTAssertFalse(popover.buttons["Fix Accessibility"].exists)
                }
                attach(popover, name: "menu-bar-\(state)-\(appearance)")
                app.terminate()
            }
        }
    }
}
