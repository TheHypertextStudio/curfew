import Combine
import CurfewKit
import Foundation
import IOKit
import OSLog

private let deviceLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "device-registry"
)

/// One Mac's row in the cross-device awareness table.
///
/// `nonisolated` so the pure, `nonisolated` `DeviceRegistry.mergeDevices`
/// can construct rows without hopping to the main actor — the project
/// builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would
/// otherwise infer a `@MainActor` initializer for this plain value type.
public nonisolated struct DeviceSummary: Identifiable, Equatable, Codable {
    /// Stable per-Mac identifier — sourced from `IOPlatformUUID` so it
    /// survives app reinstalls (but not logic-board swaps).
    public let id: String
    /// Human-readable Mac name, matching what macOS shows in Sharing.
    public let deviceName: String
    /// Timestamp of the most recent heartbeat from this device.
    public let lastSeen: Date
    /// `true` when this row describes the Mac running the current
    /// process and the user isn't idle. Drives the active/idle dot in
    /// Settings → Devices.
    public let isActiveLocal: Bool

    /// Memberwise initialiser. Kept explicit so the struct stays
    /// `public` with a documented, stable public API.
    public init(id: String, deviceName: String, lastSeen: Date, isActiveLocal: Bool) {
        self.id = id
        self.deviceName = deviceName
        self.lastSeen = lastSeen
        self.isActiveLocal = isActiveLocal
    }
}

/// Device-awareness subsystem: heartbeat writer, active-device publisher,
/// and the thin CloudKit adapter that folds heartbeats from other Macs
/// into a cross-device view.
///
/// Lifecycle: the app model starts the registry when both
/// `featureFlags.cloudSyncEnabled` and `licenseGate.isPlusUnlocked`
/// flip true. Heartbeats are written every 60 s while the user is
/// active (paused during idle to avoid burning CloudKit quota on a
/// sleeping Mac); other devices receive the change via `CKSubscription`
/// push notifications wired up in `CloudKitSyncEngine`.
///
/// In v0.1 builds (no subscriptions) the registry still works — it just
/// writes heartbeats locally and surfaces the local device only. Pro
/// gating is the caller's responsibility; the registry never reads
/// `licenseGate` directly.
@MainActor
final class DeviceRegistry: ObservableObject {
    /// Active devices (heartbeat within `activeThresholdSeconds`), including
    /// the local one. Empty until the first heartbeat lands.
    @Published private(set) var activeDevices: [DeviceSummary] = []

    /// Seconds since the last heartbeat, beyond which a device drops off
    /// `activeDevices`. 120 s per the plan.md §F15 spec.
    nonisolated static let activeThresholdSeconds: TimeInterval = 120

    /// Heartbeat cadence. 60 s matches the product spec; shorter would
    /// burn CloudKit quota for no user-visible gain.
    static let heartbeatIntervalSeconds: TimeInterval = 60

    private var heartbeatTimer: Timer?
    private let idleWatcher: IdleWatcher
    private let deviceID: String
    private let deviceName: String

    /// The in-flight `Device` upsert kicked off by `start()`. Retained so a
    /// test can await it deterministically (the upsert is fire-and-forget in
    /// production so `start()` never blocks the main actor on CloudKit).
    private var pendingRegistration: Task<Void, Never>?

    /// CloudKit adapter, or `nil` when sync is off (and in the unit-test
    /// host) — in which case the registry surfaces only the local device.
    /// Injected at construction (tests) or via ``attachStore(_:)`` (the app
    /// model, once sync arms).
    private var store: DeviceRecordSyncing?

    /// Creates a registry for the given idle watcher and optional CloudKit
    /// `store`. Tests pass either a `nil` store (heartbeat state machine
    /// only) or an in-memory `DeviceRecordSyncing` stub; production injects
    /// a `CloudKitDeviceStore` only when sync is armed and the process is
    /// not a unit-test host.
    init(
        idleWatcher: IdleWatcher,
        store: DeviceRecordSyncing? = nil,
        deviceID: String = DeviceRegistry.localDeviceID(),
        deviceName: String = DeviceRegistry.localDeviceName()
    ) {
        self.idleWatcher = idleWatcher
        self.store = store
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    /// Attaches the CloudKit adapter before `start()`. Called by the app
    /// model when sync arms so the registry can write `Device` records and
    /// fold in other Macs. A no-op once the heartbeat timer is running so a
    /// re-arm mid-session doesn't swap the store under a live cadence.
    func attachStore(_ store: DeviceRecordSyncing) {
        guard heartbeatTimer == nil else { return }
        self.store = store
    }

    /// Starts periodic heartbeats. Idempotent — no-op on repeat calls.
    func start() {
        guard heartbeatTimer == nil else { return }
        deviceLogger.info("DeviceRegistry starting heartbeat cadence")
        // Seed `activeDevices` with the local device immediately so the
        // Settings → Devices panel isn't blank for the first 60 seconds.
        activeDevices = [
            DeviceSummary(
                id: deviceID,
                deviceName: deviceName,
                lastSeen: Date(),
                isActiveLocal: true
            )
        ]
        // Register this Mac as a `Device` row so it appears in Settings →
        // Devices on every other Mac on the account.
        if let store {
            let registration = localRecord(at: Date())
            pendingRegistration = Task { await store.upsertDevice(registration) }
        }
        sendHeartbeat()
        Task { await refreshRemoteDevices() }
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeatIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
                await self?.refreshRemoteDevices()
            }
        }
    }

    /// Cancels the heartbeat timer. Safe to call when already stopped.
    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        deviceLogger.info("DeviceRegistry stopped")
    }

    /// Fires one heartbeat: writes `DeviceActivity` with the current
    /// timestamp + idle-aware active flag. Skipped entirely if the store is
    /// nil (sync off) — in that case we still update the local
    /// `activeDevices` entry so single-device users see their own name in
    /// the Devices panel.
    private func sendHeartbeat() {
        let now = Date()
        // Update the local row in place; remote rows (if any) are
        // preserved so a heartbeat doesn't blank out other Macs between
        // remote fetches.
        activeDevices = Self.mergeDevices(
            localID: deviceID,
            localName: deviceName,
            localActive: !idleWatcher.isIdle,
            remotes: lastRemotes,
            now: now
        )

        guard let store else { return }
        let record = localRecord(at: now)
        Task { await store.writeHeartbeat(record) }
    }

    /// Last batch of remote records seen, retained so a local heartbeat can
    /// re-merge without re-fetching and so the panel doesn't flicker
    /// between fetches.
    private var lastRemotes: [RemoteDeviceRecord] = []

    /// Fetches other Macs' `Device` / `DeviceActivity` records and folds
    /// them into `activeDevices`. No-op without a store.
    private func refreshRemoteDevices() async {
        guard let store else { return }
        let remotes = await store.fetchRemoteDevices()
        lastRemotes = remotes
        activeDevices = Self.mergeDevices(
            localID: deviceID,
            localName: deviceName,
            localActive: !idleWatcher.isIdle,
            remotes: remotes,
            now: Date()
        )
    }

    /// Test hook: forces a synchronous remote-device fold. Production drives
    /// the same path from the heartbeat timer.
    func refreshRemoteDevicesForTesting() async {
        await refreshRemoteDevices()
    }

    /// Test hook: awaits the in-flight `Device` upsert started by `start()`.
    /// Production never needs this — the upsert is fire-and-forget — but a
    /// synchronous test can't otherwise observe the detached write.
    func awaitPendingRegistrationForTesting() async {
        await pendingRegistration?.value
    }

    /// Folds remote `Device` / `DeviceActivity` records into the active list
    /// alongside the local Mac. Pure — no clock or CloudKit dependency, so
    /// it tests in isolation.
    ///
    /// Rules: the local device is always present and is the only row flagged
    /// `isActiveLocal`. Remote rows are dropped when soft-deleted, stale
    /// (last seen beyond `activeThresholdSeconds`), or a duplicate of the
    /// local device. Ordering is local-first, then by most-recent heartbeat.
    nonisolated static func mergeDevices(
        localID: String,
        localName: String,
        localActive: Bool,
        remotes: [RemoteDeviceRecord],
        now: Date
    ) -> [DeviceSummary] {
        let local = DeviceSummary(
            id: localID,
            deviceName: localName,
            lastSeen: now,
            isActiveLocal: localActive
        )
        let remoteSummaries = remotes
            .filter { $0.deviceID != localID && !$0.removed }
            .filter { now.timeIntervalSince($0.lastSeen) <= activeThresholdSeconds }
            .sorted { $0.lastSeen > $1.lastSeen }
            .map {
                DeviceSummary(
                    id: $0.deviceID,
                    deviceName: $0.deviceName,
                    lastSeen: $0.lastSeen,
                    isActiveLocal: false
                )
            }
        return [local] + remoteSummaries
    }

    /// The local Mac as a `RemoteDeviceRecord` for upsert / heartbeat
    /// writes at `now`.
    private func localRecord(at now: Date) -> RemoteDeviceRecord {
        RemoteDeviceRecord(
            deviceID: deviceID,
            deviceName: deviceName,
            lastSeen: now,
            isActive: !idleWatcher.isIdle,
            removed: false
        )
    }

    // MARK: - Local device identification

    /// Stable per-Mac identifier. Uses IOPlatformUUID which persists across
    /// reboots and app reinstalls (but not across logic-board swaps).
    nonisolated static func localDeviceID() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else {
            return ProcessInfo.processInfo.globallyUniqueString
        }
        defer { IOObjectRelease(service) }
        guard
            let uuid = IORegistryEntryCreateCFProperty(
                service,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String
        else {
            return ProcessInfo.processInfo.globallyUniqueString
        }
        return uuid
    }

    /// Human-readable Mac name, matching what macOS shows in Sharing.
    nonisolated static func localDeviceName() -> String {
        if let localized = Host.current().localizedName, !localized.isEmpty {
            return localized
        }
        if !ProcessInfo.processInfo.hostName.isEmpty {
            return ProcessInfo.processInfo.hostName
        }
        return "Mac"
    }
}
