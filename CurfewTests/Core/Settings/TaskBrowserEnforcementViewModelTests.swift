@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct TaskBrowserEnforcementViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test("Fresh setup and a live paused task are ready for enforcement")
    func freshSetupIsReady() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(
                docketConnectedOnce: true,
                chromeConnectedOnce: true,
                enforcementEnabled: true
            ),
            isAuthorized: true,
            lastSuccessfulPoll: now.addingTimeInterval(-30),
            docketIsHealthy: true,
            nativeHealth: .init(
                extensionOrigin: "chrome-extension://curfew",
                extensionSeenAt: now.addingTimeInterval(-10),
                hostSeenAt: now.addingTimeInterval(-10),
                isHealthy: true
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: policy(tracking: .paused, breakEndsAt: nil),
            canBeginBreak: true,
            now: now
        )

        #expect(viewModel.docketAuthorization.isHealthy)
        #expect(viewModel.docketPoll.isHealthy)
        #expect(viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.nativeHost.isHealthy)
        #expect(viewModel.enforcementReadiness.isHealthy)
        #expect(viewModel.activeTaskTitle == "Complete LVBT social strategy")
        #expect(viewModel.canToggleEnforcement)
        #expect(viewModel.enforcementEnabled)
        #expect(viewModel.canBeginBreak)
        #expect(viewModel.breakEndsAt == nil)
        #expect(!viewModel.statusSummary.isEmpty)
    }

    @Test("A stale extension heartbeat is unhealthy without revoking setup")
    func staleHeartbeatIsUnhealthy() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(
                docketConnectedOnce: true,
                chromeConnectedOnce: true,
                enforcementEnabled: true
            ),
            isAuthorized: true,
            lastSuccessfulPoll: now,
            docketIsHealthy: true,
            nativeHealth: .init(
                extensionOrigin: "chrome-extension://curfew",
                extensionSeenAt: now.addingTimeInterval(-61),
                hostSeenAt: now.addingTimeInterval(-10),
                isHealthy: false
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: policy(tracking: .paused, breakEndsAt: now.addingTimeInterval(-1)),
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.extensionHeartbeat.detail == "Last seen 1 minute ago")
        #expect(viewModel.nativeHost.isHealthy)
        #expect(!viewModel.enforcementReadiness.isHealthy)
        #expect(viewModel
            .statusSummary == "Open Chrome and check that the Curfew extension is enabled.")
        #expect(viewModel.canToggleEnforcement)
        #expect(viewModel.enforcementEnabled)
        #expect(!viewModel.canBeginBreak)
        #expect(viewModel.breakEndsAt == nil)
    }

    @Test("A missing extension heartbeat is shown as never")
    func missingHeartbeatIsNever() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(),
            isAuthorized: false,
            lastSuccessfulPoll: nil,
            docketIsHealthy: false,
            nativeHealth: .init(
                extensionOrigin: "",
                extensionSeenAt: .distantPast,
                hostSeenAt: .distantPast,
                isHealthy: false
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: nil,
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.extensionHeartbeat.detail == "Never")
        #expect(!viewModel.nativeHost.isHealthy)
    }

    @Test("Missing setup keeps enforcement off and disabled")
    func missingSetupDisablesToggle() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(),
            isAuthorized: false,
            lastSuccessfulPoll: nil,
            docketIsHealthy: false,
            nativeHealth: nil,
            hostIsInstalled: false,
            installationError: "Chrome browser integration could not be installed.",
            policy: nil,
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.docketAuthorization.isHealthy)
        #expect(!viewModel.nativeHost.isHealthy)
        #expect(!viewModel.enforcementReadiness.isHealthy)
        #expect(!viewModel.canToggleEnforcement)
        #expect(!viewModel.enforcementEnabled)
        #expect(viewModel.statusSummary == "Website limits are off.")
        #expect(viewModel.activeTaskTitle == nil)
    }

    private func policy(
        tracking: DocketTrackingState,
        breakEndsAt: Date?
    ) -> BrowserPolicySnapshot {
        .init(
            schemaVersion: "browser-policy/1",
            sessionID: UUID(),
            task: .init(id: "task-lvbt", title: "Complete LVBT social strategy"),
            tracking: tracking,
            scopes: [],
            grants: [],
            breakEndsAt: breakEndsAt,
            connectionIsHealthy: true,
            generatedAt: now
        )
    }
}
