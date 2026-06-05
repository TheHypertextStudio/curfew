import XCTest

/// Drives the app through each demo-fixture scenario and saves a screenshot
/// as a `.keepAlways` attachment. This is the CI / debug capture tier: the
/// XCUITest screenshot API needs no Screen Recording permission, so it works
/// on headless GitHub runners where `screencapture` cannot. Windowed scenarios
/// grab the app window element (z-order-independent); overlay scenarios grab
/// the full screen.
///
/// `scripts/extract-screenshots.sh` pulls the attachments out of the result
/// bundle into `build/screenshots/`. The higher-fidelity, shadowed per-window
/// stills and the walkthrough video are produced locally by
/// `scripts/capture-marketing.sh` / `scripts/capture-video.sh` instead.
///
/// Each scenario token here must match a `DemoScenario` raw value in the app
/// (`Curfew/App/Demo/DemoFixture.swift`).
final class MarketingCaptureTests: XCTestCase {
    // One throwaway launch to absorb the macOS XCUITest "first launch settles
    // in the background" penalty, so the very first real scenario already
    // foregrounds and registers its window. Without this the alphabetically
    // first scenario tends to capture the operator's desktop instead.
    // (XCTest's setUp override must be `class func`, not `static`.)
    // swiftlint:disable:next static_over_final_class
    override class func setUp() {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = "overview"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        app.terminate()
    }

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

    /// Overlay scenarios render a full-screen NSWindow that isn't part of the
    /// app's accessibility window tree, so they must be grabbed off the screen.
    @MainActor func testCaptureWarning() {
        capture(named: "warning", scenario: "warning", fullScreen: true)
    }

    @MainActor func testCaptureLockout() {
        capture(named: "lockout", scenario: "lockout", fullScreen: true)
    }

    /// Launches the app in `scenario`, waits for it to settle, and attaches a
    /// screenshot under a stable `curfew-<named>` name.
    ///
    /// Windowed scenarios screenshot the app **window element**, which XCUITest
    /// captures regardless of z-order — so a launch that lands in the
    /// background (a known first-launch XCUITest quirk on macOS) yields the
    /// Curfew window rather than whatever happens to be frontmost on the
    /// operator's desktop. Overlay scenarios fall back to the full screen.
    @MainActor
    private func capture(named: String, scenario: String, fullScreen: Bool = false) {
        let app = XCUIApplication()
        app.launchEnvironment["CURFEW_DEMO_FIXTURE"] = "1"
        app.launchEnvironment["CURFEW_DEMO_SCENARIO"] = scenario
        app.launch()

        // Demo mode self-activates, but nudge it if the launch settled in the
        // background and wait softly — never hard-assert, so a hiccup can't
        // block the capture.
        if app.state != .runningForeground {
            app.activate()
        }
        _ = app.wait(for: .runningForeground, timeout: 10)

        // For windowed scenarios, wait for the window element to register and
        // re-activate if it hasn't — then we screenshot the window itself,
        // which is captured regardless of z-order.
        let window = app.windows.firstMatch
        if !fullScreen, !window.waitForExistence(timeout: 6) {
            app.activate()
            _ = window.waitForExistence(timeout: 6)
        }

        // Let the first frame, window placement, and any overlay settle before
        // the shot. Demo mode pins state, so there is nothing animating to race.
        Thread.sleep(forTimeInterval: 2.0)

        let screenshot = (fullScreen || !window.exists)
            ? XCUIScreen.main.screenshot()
            : window.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "curfew-\(named)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }
}
