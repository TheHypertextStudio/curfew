import Combine
import Foundation

/// License- / flag-reactive glue for `CurfewAppModel`. Lives in its own
/// file so `+Lifecycle.swift` stays under the file-length lint budget
/// and readers looking for "why did CloudKit start?" find it here rather
/// than buried in the tick loop.
@MainActor
extension CurfewAppModel {
    /// Subscribes to license activation/deactivation so Pro engines start
    /// or stop without requiring an app relaunch. Debounces via the main
    /// run loop so the didSet cascade settles before engines bounce.
    func subscribeToLicenseChanges() {
        licenseGate.$activatedKey
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileProGatedModules()
            }
            .store(in: &cancellables)
    }

    /// Starts or stops CloudKit, Calendar, DeviceRegistry, and the
    /// privileged helper based on the current `FeatureFlags` +
    /// `LicenseGate` combination. Idempotent: each engine's `start()`
    /// guards against repeated activation, and `stop()` is safe to call
    /// on an already-stopped engine.
    func reconcileProGatedModules() {
        let pro = licenseGate.isProUnlocked

        if featureFlags.cloudSyncEnabled, pro {
            cloudKitSyncEngine.start(
                localSettings: settings,
                localModifiedAt: Date()
            )
            cloudKitSyncEngine.pullLockoutState()
            deviceRegistry.start()
        } else {
            cloudKitSyncEngine.stop()
            deviceRegistry.stop()
        }

        if featureFlags.calendarEnabled, pro {
            calendarMonitor.requestAccessAndSync()
        } else {
            calendarMonitor.stop()
        }

        if featureFlags.privilegedHelperEnabled {
            privilegedHelperManager.refreshStatus()
        }
    }
}
