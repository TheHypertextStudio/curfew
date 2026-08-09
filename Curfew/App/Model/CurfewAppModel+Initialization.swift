import Foundation

/// Post-`super.init()` wiring for `CurfewAppModel` plus the `static` seed
/// helpers the designated initialiser calls. Split from the main class so the
/// initialiser body stays within the lint budget and closure-capturing setup
/// (which must run after `super.init()`) lives in one obvious place.
@MainActor
extension CurfewAppModel {
    /// Finishes constructing the model after `super.init()`: pushes the initial
    /// widget snapshot, wires the idle-state callback, and installs the
    /// notification, MCP, CloudKit, and license-change wiring.
    ///
    /// - Parameter loadedSettings: The settings loaded during init, forwarded
    ///   to the first widget shared-state sync.
    func completeInitialization(with loadedSettings: CurfewSettings) {
        // No-op unless the widget is enabled (`syncWidgetSharedState` guards
        // `widgetKitEnabled` internally), so a default install — and every
        // demo / capture launch — never touches the App Group container here.
        syncWidgetSharedState(loadedSettings)

        idleWatcher.onIdleStateChanged = { [weak self] idle in
            self?.setIdleState(idle)
        }

        reflectionState.configuration = settingsStore.loadReflectionConfiguration()
        seedReflectionGatesResolvedToday()
        configureNotificationCallback()
        enableLiveProtectedWorkDetection()
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
        if featureFlags.mcpServerEnabled, settings.mcpEnabled {
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
        refreshSubscriptionLicenseIfNeeded()
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
