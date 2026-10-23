import AppKit
import CurfewKit
import Foundation

@MainActor
extension CurfewAppModel {
    /// Arms enforcement once setup is complete; isolated demos remain disarmed.
    func start() {
        guard !isDemoSession || isBackgroundAcceptanceSession,
              settings.hasCompletedInitialSetup, !started,
              !privilegedHelperManager.maintenancePaused,
              !privilegedHelperManager.repairInProgress else { return }
        started = true
        notificationManager.requestPermissionIfNeeded()
        backgroundServiceManager.ensureRegistered()
        installRespawnGuardIfNeeded()
        startEnforcementReassertionObservers()
        if featureFlags.privilegedHelperEnabled {
            Task { await reconcilePrivilegedDaemonState() }
        }
        tick()
        if !RuntimeEnvironment.isUnitTestHost {
            enforcementActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Curfew schedule enforcement"
            )
        }
        beginDisplayClock()
    }

    func stopEnforcementForUninstall() {
        timer?.invalidate()
        timer = nil
        started = false
        if let enforcementActivity {
            ProcessInfo.processInfo.endActivity(enforcementActivity)
            self.enforcementActivity = nil
        }
        for observer in reassertionObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        reassertionObservers.removeAll()
        cancellables.removeAll()
        shutdownWorkflow = ShutdownWorkflow()
        lockoutKeyInterceptor.stop()
        state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        reconcileEnforcementOwnership()
        overlayCoordinator.updateOverlays(
            for: state,
            model: self, lockoutMessage: lockoutMessage
        )
        shutDownPresence()
        browserNativeRuntime.stop()
        mcpRequestMonitor.stop()
        mcpSocketServer.stop()
        cloudKitSyncEngine.stop()
        accountSyncEngine.stop()
        calendarMonitor.stop()
        deviceRegistry.stop()
    }
}
