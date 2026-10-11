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

    @Test("Off describes the local schedule without promising the Mac cannot lock")
    func offAndRecoveryCopy() throws {
        let today = try source("Curfew/UI/Destinations/TodayView.swift")
        #expect(!today.contains("Your Mac won't lock tonight"))
        let removal = try source("Curfew/UI/SettingsView+UninstallPanel.swift")
        #expect(!removal.contains("Curfew could not remove its privileged helper."))
        let account = try source("Curfew/UI/SettingsView+SyncPanel.swift")
        #expect(account.contains("\"Get Curfew\""))
        #expect(account.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .contains(
                "CurfewServiceEndpoints.production.accountPortal.deletingLastPathComponent()"
            ))
    }

    @Test("Remote readiness requires an authenticated helper, not only a heartbeat file")
    func remoteReadiness() throws {
        let helper = try source("Curfew/App/Infrastructure/PrivilegedHelperManager.swift")
        #expect(helper.contains("guard isDaemonResponding, connectionState == .ready"))
        let panel = try source("Curfew/UI/SettingsView+SyncPanel.swift")
        let settings = try source("Curfew/UI/SettingsView.swift")
        #expect(settings.contains("await model.privilegedHelperManager.reconcileDaemonStatus()"))
        #expect(!panel.contains("Install Privileged Helper"))
        #expect(panel.contains("SMAppService.openSystemSettingsLoginItems()"))
    }

    @Test("Account errors never claim local protection is active without its state")
    func accountStatusCopy() throws {
        let copy = try source("Curfew/UI/AccountConnectionPresentation.swift")
        #expect(!copy.contains("still protected"))
        #expect(!copy.contains("Local protection continues"))
        #expect(!copy.contains("this Curfew build"))
        #expect(!copy.contains("Check its helper"))
    }

    @Test("Capture validation rejects cropped window images")
    func uncroppedCapture() throws {
        let capture = try source("CurfewUITests/MarketingCaptureTests.swift")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        #expect(capture.contains("screenshot.image.size.width, element.frame.width"))
        #expect(capture.contains("screenshot.image.size.height, element.frame.height"))
    }

    @Test("Contradictory states have isolated fixtures for remote review")
    func stateFixtures() throws {
        let fixtures = try source("Curfew/App/Model/CurfewAppModel+DemoReview.swift")
        for state in [
            "todayOffLocked",
            "setupReview",
            "assistantMalformed",
            "accountOffline",
            "accountSignInRequired",
            "accountHelperUnavailable",
            "accountUpdateFailed",
            "accountHelperHidden"
        ] {
            #expect(fixtures.contains(state))
        }
    }

    @Test("Unavailable shutdown explains the supported version without build jargon")
    func shutdownCopy() throws {
        let copy = try source("Curfew/UI/SystemSurfaceModels.swift")
        #expect(copy.contains("Install Curfew from the official website"))
        #expect(!copy.contains("unavailable in this build"))
        #expect(!copy.contains("signed release"))
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

    @Test("The menu hides extension grants while Curfew is off")
    func menuOffExtension() throws {
        let content = try source("Curfew/ContentView.swift")
        #expect(content.contains("if model.isEnforcementRunning, snapshot.canRequestExtension"))
    }

    @Test("Today does not render a lock countdown after the scheduled lock")
    func lockedCountdown() throws {
        let today = try source("Curfew/UI/Destinations/TodayView.swift")
        #expect(today.contains("let hasWindow = !isLocked"))
    }

    @Test("Completed setup review does not depend on a stale walkthrough cursor")
    func setupReviewContent() throws {
        let setup = try source("Curfew/UI/GettingStartedView.swift")
        #expect(setup
            .contains(
                "if model.settings.hasCompletedInitialSetup || flow.currentStep == .confirmation"
            ))
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
