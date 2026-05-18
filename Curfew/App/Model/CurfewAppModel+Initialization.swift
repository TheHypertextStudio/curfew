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
            settings = mergedSettingsApplyingRemote(remoteSettings)
            settingsStore.save(settings)
            syncWidgetSharedState(settings)
        }
        cloudKitSyncEngine.onLockoutStateReceived = { [weak self] snapshot in
            self?.warningStagesFiredToday.formUnion(snapshot.warningStagesFired)
        }
        subscribeToLicenseChanges()
        reconcileProGatedModules()
    }

    /// Merges a remote settings payload with the live local copy, deferring
    /// a `.weaker` schedule change when the device is currently locked.
    /// Closing M7: without this, a fast-clock device that loosens its
    /// schedule wins last-write and releases the locked device's lockout on
    /// the next sync. The C7 guard then catches it on the apply path too,
    /// but deferring at receive time keeps the local schedule in `settings`
    /// rather than silently rewriting it.
    private func mergedSettingsApplyingRemote(_ remote: CurfewSettings) -> CurfewSettings {
        var merged = remote
        guard state.phase == .locked else { return merged }
        let classification = policyEngine.classifyChange(
            from: settings.schedule,
            to: remote.schedule
        )
        guard classification == .weaker else { return merged }
        merged.schedule = settings.schedule
        merged.pendingScheduleChange = PendingScheduleChange(
            proposedSchedule: remote.schedule,
            requestedAt: currentTime,
            effectiveAt: currentTime,
            classification: .weaker
        )
        return merged
    }
}
