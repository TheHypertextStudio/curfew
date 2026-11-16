import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// In-app escape routes that must stay closed while the curfew holds: uninstall,
/// Settings opened from the rest screen, and quitting.
@MainActor
struct LockoutBypassGuardTests {
    private let locked = CurfewEvaluation(
        phase: .locked, warningStage: .lockout, minutesRemaining: 0,
        canRequestExtension: false, lockDate: nil, unlockDate: nil
    )

    private func makeModel(router: AppRouterSpy? = nil) -> CurfewAppModel {
        let suite = "CurfewLockoutGuardTests.\(UUID().uuidString)"
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: UserDefaults(suiteName: suite)!),
            appRouter: router ?? AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore()
        )
    }

    @Test("Uninstall is refused while lockout is enforced")
    func uninstallBlockedDuringLockout() {
        let model = makeModel()
        #expect(!model.uninstallIsBlockedByCurfew)
        model.state = locked
        #expect(model.uninstallIsBlockedByCurfew)
        #expect(CurfewAppModel
            .uninstallBlockedMessage == "Uninstall is available once curfew lifts.")
    }

    @Test("Uninstall is refused while a durable deadline is still running")
    func uninstallBlockedByDurableDeadline() {
        let model = makeModel()
        model.currentTime = Date(timeIntervalSince1970: 1_800_000_000)
        model.lockoutDeadlineStore.save(LockoutDeadlineRecord(
            lockoutStartedAt: model.currentTime.addingTimeInterval(-60),
            scheduledUnlockAt: model.currentTime.addingTimeInterval(3600),
            kind: .scheduledTime
        ))
        #expect(model.uninstallIsBlockedByCurfew)
        model.currentTime = model.currentTime.addingTimeInterval(7200)
        #expect(!model.uninstallIsBlockedByCurfew)
    }

    @Test("Rest screen actions never open Settings behind the lockout")
    func restActionsDoNotOpenSettings() {
        let router = AppRouterSpy()
        let model = makeModel(router: router)
        model.state = locked
        model.openRestScreenSetup()
        model.restNow()
        #expect(router.showSettingsCallCount == 0)
        #expect(router.activateCallCount == 0)
        #expect(!model.canRestNow)
    }

    @Test("Quit is vetoed during lockout but not for logout, restart, or shutdown")
    func quitVetoedDuringLockout() {
        let model = makeModel()
        let delegate = AppDelegate()
        delegate.model = model
        var sessionEnding = false
        delegate.systemSessionEndingProbe = { sessionEnding }

        #expect(model.allowsQuit)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        model.state = locked
        #expect(!model.allowsQuit)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
        sessionEnding = true
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }
}
