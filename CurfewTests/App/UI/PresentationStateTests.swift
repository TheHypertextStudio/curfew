@testable import Curfew
import Foundation
import Testing

struct PresentationStateTests {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("Account sync enrollment hides the stopped legacy iCloud service")
    func canonicalSync() throws {
        let panel = try source("Curfew/UI/SettingsView+InfoPanels.swift")
        #expect(panel
            .contains(
                "model.featureFlags.cloudSyncEnabled, !model.settings.accountSync.isEnrolled"
            ))
    }

    @Test("Long assistant explanations remain scrollable with decision buttons available")
    func consentLayout() throws {
        let sheet = try source("Curfew/UI/MCPConsentSheet.swift")
        #expect(sheet.contains("ScrollView"))
        #expect(sheet
            .contains("presentation.canApprove ? \"Allow this change?\" : \"Request unavailable\""))
    }

    @Test("Browser settings explain readiness without exposing diagnostic rows by default")
    func browserCopy() throws {
        let panel = try source("Curfew/UI/SettingsView+TaskBrowserEnforcement.swift")
        #expect(panel.contains("static let title = \"Websites during work\""))
        #expect(panel.contains("DisclosureGroup(\"Connection details\")"))
        #expect(panel.contains("controller.viewModel.statusSummary"))
        #expect(!panel.contains("retained active work session"))
    }

    @Test("Scheduled lock time never claims protection is active when Curfew is off")
    func todayOffState() throws {
        let today = try source("Curfew/UI/Destinations/TodayView.swift")
        #expect(today.contains("isLocked: isLocked && model.isEnforcementRunning"))
        #expect(today.contains("emptyNoteActionable: !(isLocked && model.isEnforcementRunning)"))
        #expect(today.contains("Curfew is off. Review your schedule."))
    }

    @Test("Finish Setup opens the walkthrough instead of arming defaults")
    func setupAction() throws {
        let today = try source("Curfew/UI/Destinations/TodayView.swift")
        #expect(today.contains("model.showGettingStarted()"))
        #expect(!today.contains("model.completeInitialSetup()"))
    }

    @Test("Returning setup review dismisses without changing protection")
    func returningSetup() throws {
        let setup = try source("Curfew/UI/GettingStartedView.swift")
        #expect(setup.contains("Button(\"Done\")"))
        #expect(setup.contains("Text(\"Review setup\")"))
        #expect(setup
            .contains("model.isEnforcementRunning ? \"Curfew is on.\" : \"Curfew is off.\""))
    }

    @Test("Authentication failure explains the problem without blaming the user or build")
    func helperFailureCopy() throws {
        let health = EnforcementHealth.degradedHelperUnauthorized
        #expect(health.settingsStatusTitle == "Can't verify Curfew")
        #expect(health.bannerDetail?.contains("official website") == true)
        #expect(health.compactPopoverMessage?.contains("verify Curfew") == true)
        let panel = try source("Curfew/UI/SettingsView+PrivilegedHelperPanel.swift")
        #expect(!panel.contains("This build was rejected"))
        #expect(!panel.contains("reinstall a signed release"))
    }
}
