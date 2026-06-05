import XCTest

/// Drives the app through each demo-fixture scenario and saves a full-screen
/// screenshot as a `.keepAlways` attachment. This is the CI / debug capture
/// tier: `XCUIScreen.screenshot()` needs no Screen Recording permission, so it
/// works on headless GitHub runners where `screencapture` cannot.
///
/// `scripts/extract-screenshots.sh` pulls the attachments out of the result
/// bundle into `build/screenshots/`. The higher-fidelity, shadowed per-window
/// stills and the walkthrough video are produced locally by
/// `scripts/capture-marketing.sh` / `scripts/capture-video.sh` instead.
///
/// Each scenario token here must match a `DemoScenario` raw value in the app
/// (`Curfew/App/Demo/DemoFixture.swift`).
final class MarketingCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        // Keep going if an activation hiccup logs a failure mid-test so we
        // still capture (and attempt the remaining scenarios).
        continueAfterFailure = true
    }

    @MainActor func testCaptureOverview() {
        capture(named: "overview", scenario: "overview")
    }

    @MainActor func testCaptureConfiguration() {
        capture(named: "configuration", scenario: "configuration")
    }

    @MainActor func testCaptureSettings() {
        capture(named: "settings", scenario: "settings")
    }

    @MainActor func testCaptureGettingStarted() {
        capture(named: "getting-started", scenario: "getting-started")
    }

    @MainActor func testCaptureThisWeek() {
        capture(named: "this-week", scenario: "this-week")
    }

    @MainActor func testCaptureWarning() {
        capture(named: "warning", scenario: "warning")
    }

    @MainActor func testCaptureLockout() {
        capture(named: "lockout", scenario: "lockout")
    }

    /// Launches the app in `scenario`, waits for it to settle, captures the
    /// full screen, and attaches it under a stable `curfew-<named>` name.
    @MainActor
    private func capture(named: String, scenario: String) {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = scenario
        app.launch()

        // Demo mode self-activates, but nudge it if the launch settled in the
        // background (a known first-launch XCUITest quirk on macOS) and wait
        // softly — never hard-assert, so a hiccup can't block the capture.
        if app.state != .runningForeground {
            app.activate()
        }
        _ = app.wait(for: .runningForeground, timeout: 10)

        // Let the first frame, window placement, and any overlay settle before
        // the shot. Demo mode pins state, so there is nothing animating to race.
        Thread.sleep(forTimeInterval: 2.0)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "curfew-\(named)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}
