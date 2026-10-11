import AppKit
@testable import Curfew
@testable import CurfewKit
import Foundation
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
    @Test("Shutdown panel explains availability without build jargon")
    func unavailableStateCarriesReleaseGuidance() {
        #expect(ShutdownPanelState.resolve(isAvailable: true) == .available)

        let unavailable = ShutdownPanelState.resolve(isAvailable: false)
        guard case .unavailable(let message) = unavailable else {
            Issue.record("Expected unavailable shutdown panel state.")
            return
        }

        #expect(message.contains("official website"))
        #expect(!message.contains("entitlement"))
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
                == "Installed."
        )
        #expect(
            PrivilegedHelperStatusCopy.daemonDescription(for: .requiresApproval)
                == "Approval needed in System Settings."
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
    @Test("Copying a Recovery Key puts that key on the selected pasteboard")
    func recoveryKeyCanBeCopied() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("curfew-test-\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }

        #expect(AccountRecoveryKeyClipboard.copy("TEST-RECOVERY-KEY", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "TEST-RECOVERY-KEY")
    }

    @Test("Saving a Recovery Key replaces an existing file without exposing it to other users")
    func recoveryKeyExportUsesOwnerOnlyFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "curfew-recovery-key-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("curfew-recovery-key.txt")
        try "old key".write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: destination.path
        )

        try AccountRecoveryKeyDocument(recoveryKey: "NEW-RECOVERY-KEY").write(to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "NEW-RECOVERY-KEY\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

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

@MainActor
struct AccountConnectionPresentationTests {
    @Test("Account status explains the live remote connection without overstating permission")
    func statesStayPlainAndAccurate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(AccountConnectionPresentation.resolve(.connecting) == .init(
            title: "Connecting this Mac…",
            detail: "Curfew is securely connecting to your account. "
                + "Your schedule is unchanged.",
            systemImage: "arrow.triangle.2.circlepath",
            tone: .neutral,
            lastConfirmedAt: nil
        ))
        #expect(AccountConnectionPresentation.resolve(.synchronized(now)) == .init(
            title: "This Mac is connected",
            detail: "Curfew is checking for remote commands. "
                + "Choose which assistants and devices have access in your account.",
            systemImage: "checkmark.circle.fill",
            tone: .ready,
            lastConfirmedAt: now
        ))
        #expect(AccountConnectionPresentation.resolve(
            .synchronized(now),
            remoteEnforcementReady: false
        ) == .init(
            title: "Remote locks are not ready",
            detail: "This Mac is signed in, but background protection cannot enforce remote "
                + "locks right now. Review Background Protection in General.",
            systemImage: "exclamationmark.triangle.fill",
            tone: .warning,
            lastConfirmedAt: now
        ))
        #expect(AccountConnectionPresentation.resolve(.pendingEncryption) == .init(
            title: "Encrypted changes are waiting to sync",
            detail: "Your encrypted changes haven’t synced yet.",
            systemImage: "lock.rotation",
            tone: .neutral,
            lastConfirmedAt: nil
        ))
        #expect(AccountConnectionPresentation.resolve(.offline) == .init(
            title: "Remote control is offline",
            detail: "Your schedule is unchanged. "
                + "Curfew will reconnect automatically.",
            systemImage: "wifi.slash",
            tone: .warning,
            lastConfirmedAt: nil
        ))
    }

    @Test("Rejected account status explains the same-account repair")
    func rejectedAccountStatusOffersRepair() {
        #expect(AccountSyncStatus.rejected("Curfew needs you to sign in again.")
            .requiresSameAccountSignIn)
        #expect(!AccountSyncStatus.rejected("Curfew Account access was rejected.")
            .requiresSameAccountSignIn)
        #expect(AccountConnectionPresentation
            .resolve(.rejected("Curfew needs you to sign in again.")) == .init(
                title: "Reconnect this Mac to Curfew",
                detail: "Curfew cannot authenticate this Mac right now. "
                    + "Sign in again with the same account to restore remote control. "
                    + "Your local schedule stays unchanged.",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                lastConfirmedAt: nil
            ))
        #expect(AccountConnectionPresentation
            .resolve(.rejected("Curfew Account access was rejected.")) == .init(
                title: "Check this Mac’s account access",
                detail: "Curfew Account denied this Mac’s request. Its device access may have "
                    + "been removed. Check this Mac in your account. Your schedule is unchanged.",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                lastConfirmedAt: nil
            ))
    }
}
