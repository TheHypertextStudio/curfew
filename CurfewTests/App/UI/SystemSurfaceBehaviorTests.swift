@testable import Curfew
import ServiceManagement
import Testing

@MainActor
struct OnboardingConfirmationRequirementTests {
    @Test("Confirmation step exposes outstanding onboarding requirements")
    func confirmationRequirementsTrackOutstandingSteps() {
        var flow = FirstRunFlow()

        #expect(flow.confirmationRequirements == [
            OnboardingConfirmationRequirement(
                id: .scheduleReview,
                title: "Schedule review still required",
                isSatisfied: false
            ),
            OnboardingConfirmationRequirement(
                id: .accessibilityGrant,
                title: "Accessibility access still required",
                isSatisfied: false
            )
        ])

        flow.markScheduleReviewed()
        #expect(flow.confirmationRequirements[0] == OnboardingConfirmationRequirement(
            id: .scheduleReview,
            title: "Schedule review complete",
            isSatisfied: true
        ))

        flow.updateAccessibilityGranted(true)
        #expect(flow.confirmationRequirements == [
            OnboardingConfirmationRequirement(
                id: .scheduleReview,
                title: "Schedule review complete",
                isSatisfied: true
            ),
            OnboardingConfirmationRequirement(
                id: .accessibilityGrant,
                title: "Accessibility access granted",
                isSatisfied: true
            )
        ])
    }
}

@MainActor
struct DeferredIntegrationVisibilityTests {
    @Test("Enabled deferred modules surface in a stable settings order")
    func visiblePanelsFollowEnabledFlags() {
        let flags = FeatureFlags(
            widgetKitEnabled: true,
            cloudSyncEnabled: true,
            mcpServerEnabled: false,
            privilegedHelperEnabled: true,
            calendarEnabled: true
        )

        #expect(DeferredFeaturePanel.visible(for: flags) == [
            .widgetKit,
            .calendar,
            .cloudSync,
            .privilegedHelper
        ])
    }
}

@MainActor
struct ShutdownPanelStateTests {
    @Test("Shutdown panel explains signed-build gating when automation entitlement is absent")
    func unavailableStateCarriesReleaseGuidance() {
        #expect(ShutdownPanelState.resolve(isAvailable: true) == .available)

        let unavailable = ShutdownPanelState.resolve(isAvailable: false)
        guard case .unavailable(let message) = unavailable else {
            Issue.record("Expected unavailable shutdown panel state.")
            return
        }

        #expect(message.contains("signed"))
        #expect(message.contains("Apple Events"))
    }

    @Test("Shutdown panel warns about the System Events consent prompt when available")
    func availableStateExplainsAutomationPrompt() {
        #expect(ShutdownPanelState.availableExplanation.contains("System Events"))
        #expect(ShutdownPanelState.availableExplanation.contains("permission"))
        #expect(ShutdownPanelState.appleEventsUsageDescription.contains("shut down your Mac"))
    }
}

@MainActor
struct PrivilegedHelperStatusCopyTests {
    @Test("Helper panel copy reflects daemon and login-item states")
    func helperStatusDescriptions() {
        #expect(
            PrivilegedHelperStatusCopy.daemonDescription(for: .enabled)
                == "Running — root-owned lockout enforcement active."
        )
        #expect(
            PrivilegedHelperStatusCopy.daemonDescription(for: .requiresApproval)
                == "Needs approval — open System Settings → Login Items."
        )
        #expect(
            PrivilegedHelperStatusCopy.loginItemDescription(for: .enabled)
                == "Curfew opens automatically at login."
        )
        #expect(
            PrivilegedHelperStatusCopy.loginItemDescription(for: .notRegistered)
                == "Not registered."
        )
    }
}

struct ScheduleSurfaceCopyTests {
    @Test("Schedule editor copy frames the schedule as work time versus blackout")
    func scheduleLabelsExplainWorkWindow() {
        #expect(ScheduleSurfaceCopy.weeklyScheduleSubtitle.contains("work"))
        #expect(ScheduleSurfaceCopy.weeklyScheduleSubtitle.contains("blocked"))
        #expect(ScheduleSurfaceCopy.workEndsLabel == "Work ends")
        #expect(ScheduleSurfaceCopy.workResumesLabel == "Work resumes")
    }
}

@MainActor
struct AccountEnrollmentCopyTests {
    @Test("Account panel explains phone locking and the safe per-device default")
    func remoteControlIsPlainAndOptIn() {
        let copy = SettingsView.accountExplanation
        #expect(copy.contains("phone"))
        #expect(copy.contains("lock this Mac"))
        #expect(copy.contains("off until you turn it on"))
    }

    @Test("Account panel separates sign-in recovery from encrypted-data recovery")
    func recoveryFactorsAreExplainedSeparately() {
        let copy = SettingsView.accountSecurityNote
        #expect(copy.contains("2FA backup codes"))
        #expect(copy.contains("Curfew Recovery Key"))
        #expect(!copy.contains("Coordinator signing secret"))
    }
}
