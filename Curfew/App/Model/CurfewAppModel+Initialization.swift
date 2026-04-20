import Foundation

@MainActor
extension CurfewAppModel {
    func completeInitialization(with loadedSettings: CurfewSettings) {
        syncWidgetSharedState(loadedSettings)

        idleWatcher.onIdleStateChanged = { [weak self] idle in
            self?.setIdleState(idle)
        }

        configureNotificationCallback()
    }

    /// Wires the notification manager's snooze callback and MCP request
    /// monitor back into the model after `super.init()` completes. Lifted
    /// out of the initialiser body because closures capturing `self` must
    /// run post-init.
    private func configureNotificationCallback() {
        notificationManager.onSnoozeRequested = { [weak self] in
            self?.requestNotificationSnooze()
        }
        mcpRequestMonitor.onNewRequests = { [weak self] requests in
            self?.handleNewMCPRequests(requests)
        }
        if settings.mcpEnabled {
            mcpRequestMonitor.start()
            mcpSocketServer.start()
        }
        licenseGate.loadStoredKey()

        cloudKitSyncEngine.onSettingsReceived = { [weak self] remoteSettings in
            guard let self else { return }
            settings = remoteSettings
            settingsStore.save(remoteSettings)
            syncWidgetSharedState(remoteSettings)
        }
        cloudKitSyncEngine.onLockoutStateReceived = { [weak self] snapshot in
            self?.warningStagesFiredToday.formUnion(snapshot.warningStagesFired)
        }
        subscribeToLicenseChanges()
        reconcileProGatedModules()
    }
}
