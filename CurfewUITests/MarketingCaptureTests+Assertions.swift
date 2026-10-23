import XCTest

extension MarketingCaptureTests {
    @MainActor
    // Exhaustive visual assertions correspond to distinct fixture states.
    // swiftlint:disable:next cyclomatic_complexity
    func assertWorkspaceState(_ state: String, in app: XCUIApplication) {
        switch state {
        case "schedule-pending": assertText("Scheduled change", in: app)
        case "schedule-applied": assertText("Schedule change applied.", in: app)
        case "schedule-overnight":
            let value = app.datePickers.firstMatch.value as? String ?? ""
            XCTAssertTrue(
                value.contains("8") || value.contains("20"),
                "Unexpected overnight time: \(value)"
            )
        case "day-off": assertText("No curfew scheduled today.", in: app)
        case "accessibility-denied": assertText("Accessibility", in: app)
        case "journal-populated": assertText(
                "Finished the project and made time for a walk.",
                in: app
            )
        case "prompts-empty":
            XCTAssertEqual(app.textFields.count, 0)
            XCTAssertTrue(app.buttons["Add prompt"].firstMatch.exists)
        case "override-cooldown":
            XCTAssertTrue(app.staticTexts["override-cooldown"].exists)
            XCTAssertFalse(app.buttons["override-hold-confirm"].isEnabled)
        case "override-invalid":
            XCTAssertEqual(app.textViews["override-reason"].value as? String, "One more task")
            XCTAssertFalse(app.buttons["override-hold-confirm"].isEnabled)
        case "override-ready": XCTAssertTrue(app.buttons["override-hold-confirm"].isEnabled)
        case "overrides-exhausted": assertText("No overrides left this week", in: app)
        case "shutdown-denied": assertText("Shutdown needs permission", in: app)
        case "shutdown-failed": assertText("Shutdown failed", in: app)
        default: XCTFail("Unasserted fixture state: \(state)")
        }
    }

    @MainActor
    func assertText(_ text: String, in app: XCUIApplication) {
        do {
            var nodes = try [app.snapshot()]
            var values: [String] = []
            while let node = nodes.popLast() {
                values.append("\(node.value ?? "") \(node.label)")
                nodes.append(contentsOf: node.children)
            }
            XCTAssertTrue(
                values.contains { $0.contains(text) },
                "Missing expected fixture text: \(text)\n\(values)"
            )
        } catch {
            XCTFail("Could not read the fixture accessibility snapshot: \(error)")
        }
    }

    @MainActor
    func assertSettingsState(_ state: String, in app: XCUIApplication) {
        if ["helper-approval", "helper-unauthorized", "helper-stale", "helper-registration"]
            .contains(state), app.disclosureTriangles["Details"].exists {
            let details = app.disclosureTriangles["Details"]
            details.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                .withOffset(CGVector(dx: 26, dy: 0)).click()
            XCTAssertTrue(["1", "on", "true"].contains(
                String(describing: details.value ?? "").lowercased()
            ), "Technical details must be expanded before capture: \(details.debugDescription)")
        }
        let text = [
            "ready": "Keyboard shortcut blocking is available",
            "accessibility-denied": "Keyboard shortcut blocking is unavailable",
            "tap-down": "Keyboard shortcut blocking was interrupted",
            "helper-approval": "Approval needed",
            "helper-unauthorized": "Can't verify Curfew",
            "helper-stale": "Connection interrupted",
            "helper-registration": "Installation failed",
            "login-approval": "Approve in System Settings",
            "assistant-pending": "Review Request",
            "claude-configured": "Added to Claude Desktop",
            "license-invalid": "That key isn't valid",
            "license-lifetime": "Lifetime", "license-subscription": "active until",
            "license-expired": "subscription has expired", "cloud-idle": "Ready to sync",
            "cloud-syncing": "Syncing", "cloud-synced": "Last synced",
            "cloud-failed": "Couldn't sync",
            "cloud-unavailable": "Sign in to iCloud",
            "calendar-denied": "Curfew needs full Calendar access to read events.",
            "calendar-empty": "0 events"
        ]
        if state == "limits-none" {
            for label in ["Extensions per week", "Overrides per week"] {
                XCTAssertEqual(app.steppers[label].value as? String, "0", label)
            }
        }
        if let expected = text[state] {
            assertText(expected, in: app)
        }
        if ["assistant-on", "assistant-read-only", "assistant-automatic", "claude-absent"]
            .contains(state) {
            XCTAssertTrue(app.popUpButtons["assistant-policy"].waitForExistence(timeout: 3))
            let policy = state == "assistant-read-only" ? "Read only"
                :
                (state == "assistant-automatic" ? "Allow changes automatically" :
                    "Ask before making changes")
            assertText(policy, in: app)
        }
    }
}
