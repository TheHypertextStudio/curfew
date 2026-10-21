import XCTest

extension CurfewUITests {
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
}
