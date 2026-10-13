import CurfewKit
import Foundation
import ServiceManagement

@MainActor
extension CurfewAppModel {
    func reconnectBackgroundProtection() async {
        guard !isDemoSession, !privilegedHelperManager.repairInProgress,
              !isEnforcementRunning,
              let enrollment = settings.accountSync.enrollment else { return }
        let wasConnected = accountSyncEngine.isActive || accountSyncEngine.isMaintenancePaused
        let hadLocalMCP = mcpRequestMonitor.isStarted || privilegedHelperManager.maintenancePaused
        let inspection = PrivilegedHelperMaintenance()
        await privilegedHelperManager.reconnectBackgroundProtection(
            quiesce: { [self] in
                mcpRequestMonitor.stop()
                mcpSocketServer.stop()
                await accountSyncEngine.pauseForMaintenance()
            },
            legacyAdmission: { [self] in
                try await inspection.admitLegacy(
                    deviceID: enrollment.deviceID,
                    requireLegacyRegistration: privilegedHelperManager
                        .daemonStatus != .notRegistered
                )
            },
            contextIsCurrent: { [self] in settings.accountSync.enrollment == enrollment },
            resume: { [self] in
                guard settings.accountSync.enrollment == enrollment else { return }
                accountSyncEngine
                    .resumeAfterMaintenance(enrollment: wasConnected ? enrollment : nil)
                if hadLocalMCP, featureFlags.mcpServerEnabled, settings.mcpEnabled {
                    mcpRequestMonitor.start()
                    mcpSocketServer.start()
                }
            }
        )
    }
}
