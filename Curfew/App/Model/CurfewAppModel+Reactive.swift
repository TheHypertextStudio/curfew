import CloudKit
import CurfewKit
import Foundation

/// License- / flag-reactive glue for `CurfewAppModel`. Lives in its own
/// file so `+Lifecycle.swift` stays under the file-length lint budget
/// and readers looking for "why did CloudKit start?" find it here rather
/// than buried in the tick loop.
@MainActor
extension CurfewAppModel {
    /// Subscribes to license activation/deactivation so Pro engines start
    /// or stop without requiring an app relaunch. Debounces via the main
    /// run loop so the `didSet` cascade settles before engines bounce.
    ///
    /// `@Observable` provides no `$publisher`, so this wires
    /// ``LicenseGate/onActivationChange`` instead. The callback fires
    /// synchronously inside the `activatedKey` `didSet`; deferring the
    /// reconcile onto the main run loop preserves the prior
    /// `receive(on: RunLoop.main)` behaviour so the activation cascade settles
    /// before engines start or stop.
    func subscribeToLicenseChanges() {
        licenseGate.onActivationChange = { [weak self] in
            RunLoop.main.perform { [weak self] in
                self?.reconcilePlusGatedModules()
            }
        }
    }

    /// Starts or stops CloudKit, Calendar, DeviceRegistry, and the
    /// privileged helper based on the current `FeatureFlags` +
    /// `LicenseGate` combination. Idempotent: each engine's `start()`
    /// guards against repeated activation, and `stop()` is safe to call
    /// on an already-stopped engine.
    func reconcilePlusGatedModules() {
        let plus = licenseGate.isPlusUnlocked

        if featureFlags.cloudSyncEnabled, plus {
            cloudKitSyncEngine.start(
                localSettings: settings,
                localModifiedAt: Date()
            )
            cloudKitSyncEngine.pullLockoutState()
            // Attach a real CloudKit adapter so this Mac writes a `Device`
            // record and folds in other Macs. Skipped in the unit-test host
            // so tests never provision CloudKit or trip a permission prompt;
            // the registry then surfaces only the local device.
            if !RuntimeEnvironment.isUnitTestHost {
                deviceRegistry.attachStore(
                    CloudKitDeviceStore(
                        container: CKContainer(
                            identifier: CloudKitSchema.containerID
                        )
                    )
                )
            }
            deviceRegistry.start()
        } else {
            cloudKitSyncEngine.stop()
            deviceRegistry.stop()
        }

        if featureFlags.calendarEnabled, plus {
            calendarMonitor.requestAccessAndSync()
        } else {
            calendarMonitor.stop()
        }

        if featureFlags.privilegedHelperEnabled {
            privilegedHelperManager.refreshStatus()
        }
    }

    /// Pulls a renewed subscription license from the Worker when the active key
    /// is a `.subscription` plan. Fire-and-forget: a successful fetch re-activates
    /// with the renewed key (extending `expiresAt`); a 404 / network failure is a
    /// no-op, leaving the stored key to lapse at its deadline. Lifetime keys (and
    /// the free tier) return immediately without touching the network. Called on
    /// launch and on the daily rollover.
    func refreshSubscriptionLicenseIfNeeded() {
        guard
            let key = licenseGate.activatedKey,
            key.plan == .subscription,
            let refreshToken = key.refreshToken
        else { return }

        let refresher = licenseRefresher
        Task { [weak self] in
            guard let renewed = await refresher.refreshedKey(for: refreshToken) else { return }
            await MainActor.run { self?.licenseGate.activate(renewed) }
        }
    }
}
