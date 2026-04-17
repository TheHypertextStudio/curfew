import CloudKit
import Combine
import Foundation
import IOKit
import OSLog

private let deviceLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "device-registry"
)

/// One Mac's row in the cross-device awareness table.
public struct DeviceSummary: Identifiable, Equatable, Codable {
    public let id: String
    public let deviceName: String
    public let lastSeen: Date
    public let isActiveLocal: Bool

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
/// `featureFlags.cloudSyncEnabled` and `licenseGate.isProUnlocked`
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
    static let activeThresholdSeconds: TimeInterval = 120

    /// Heartbeat cadence. 60 s matches the product spec; shorter would
    /// burn CloudKit quota for no user-visible gain.
    static let heartbeatIntervalSeconds: TimeInterval = 60

    private var heartbeatTimer: Timer?
    private let idleWatcher: IdleWatcher
    private let deviceID: String
    private let deviceName: String
    private let container: CKContainer?

    init(
        idleWatcher: IdleWatcher,
        container: CKContainer? = nil,
        deviceID: String = DeviceRegistry.localDeviceID(),
        deviceName: String = DeviceRegistry.localDeviceName()
    ) {
        self.idleWatcher = idleWatcher
        self.container = container
        self.deviceID = deviceID
        self.deviceName = deviceName
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
        sendHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.heartbeatIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        deviceLogger.info("DeviceRegistry stopped")
    }

    /// Fires one heartbeat: writes `DeviceActivity` with the current
    /// timestamp + idle-aware active flag. Skipped entirely if the
    /// container is nil (sync off) — in that case we still update the
    /// local `activeDevices` entry so single-device users see their own
    /// name in the Devices panel.
    private func sendHeartbeat() {
        let now = Date()
        activeDevices = [
            DeviceSummary(
                id: deviceID,
                deviceName: deviceName,
                lastSeen: now,
                isActiveLocal: !idleWatcher.isIdle
            )
        ]

        guard let container else { return }
        let recordID = CKRecord.ID(
            recordName: CloudKitSchema.deviceActivityRecordName(for: deviceID)
        )
        let record = CKRecord(
            recordType: CloudKitSchema.RecordType.deviceActivity,
            recordID: recordID
        )
        record[CloudKitSchema.Field.deviceID] = deviceID as NSString
        record[CloudKitSchema.Field.deviceName] = deviceName as NSString
        record[CloudKitSchema.Field.timestamp] = now as NSDate
        record[CloudKitSchema.Field.isActive] = NSNumber(value: !idleWatcher.isIdle)

        Task {
            do {
                _ = try await container.privateCloudDatabase.save(record)
            } catch {
                deviceLogger.debug("heartbeat save failed: \(error.localizedDescription)")
            }
        }
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
