import CloudKit
import Foundation
import OSLog

private let deviceStoreLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "device-store"
)

/// Plain-value snapshot of a `Device` / `DeviceActivity` pair for one Mac.
///
/// Crosses the CloudKit → `DeviceRegistry` boundary so the registry's merge
/// logic — and its tests — never depend on `CKRecord` internals. A single
/// value carries both the registration row (`deviceName`, `removed`) and the
/// latest heartbeat (`lastSeen`, `isActive`).
public struct RemoteDeviceRecord: Equatable, Sendable {
    /// Stable per-Mac identifier (from `IOPlatformUUID`).
    public let deviceID: String
    /// Human-readable Mac name, matching what macOS shows in Sharing.
    public let deviceName: String
    /// Most recent heartbeat observed from this device.
    public let lastSeen: Date
    /// Whether the user was actively using this Mac at `lastSeen`.
    public let isActive: Bool
    /// Soft-delete flag — a removed device is hidden from the panel until
    /// it re-registers.
    public let removed: Bool

    /// Memberwise initialiser. Explicit so the struct stays `public` with a
    /// documented, stable API surface.
    public init(
        deviceID: String,
        deviceName: String,
        lastSeen: Date,
        isActive: Bool,
        removed: Bool
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.lastSeen = lastSeen
        self.isActive = isActive
        self.removed = removed
    }
}

/// Seam over the CloudKit reads/writes `DeviceRegistry` needs for
/// cross-device awareness. Production is `CloudKitDeviceStore`; tests inject
/// an in-memory stub so the registry's state machine is exercised without a
/// `CKContainer` or any network traffic.
public protocol DeviceRecordSyncing: Sendable {
    /// Upserts the `Device` registration row for this Mac (id, name,
    /// first-/last-seen, `removed = false`).
    func upsertDevice(_ record: RemoteDeviceRecord) async

    /// Overwrites this Mac's `DeviceActivity` heartbeat record.
    func writeHeartbeat(_ record: RemoteDeviceRecord) async

    /// Fetches the `Device` + latest `DeviceActivity` for every Mac on this
    /// iCloud account, collapsed into one `RemoteDeviceRecord` each.
    func fetchRemoteDevices() async -> [RemoteDeviceRecord]
}

/// Production `DeviceRecordSyncing` backed by the user's private CloudKit
/// database. All errors are treated as soft — device awareness is a
/// convenience surface, never load-bearing for enforcement, so a CloudKit
/// outage degrades to "this Mac only" rather than surfacing an error.
public struct CloudKitDeviceStore: DeviceRecordSyncing {
    private let database: CKDatabase

    /// Wraps `container`'s private database. The container is created by the
    /// caller (the app model) only outside the unit-test host, so this type
    /// never provisions CloudKit during tests.
    public init(container: CKContainer) {
        self.database = container.privateCloudDatabase
    }

    public func upsertDevice(_ record: RemoteDeviceRecord) async {
        let id = CKRecord.ID(
            recordName: CloudKitSchema.deviceRecordName(for: record.deviceID)
        )
        let ckRecord: CKRecord
            = if let existing = try? await database.record(for: id) {
            existing
        } else {
            CKRecord(recordType: CloudKitSchema.RecordType.device, recordID: id)
        }
        ckRecord[CloudKitSchema.Field.deviceID] = record.deviceID as NSString
        ckRecord[CloudKitSchema.Field.deviceName] = record.deviceName as NSString
        ckRecord[CloudKitSchema.Field.hostname]
            = ProcessInfo.processInfo.hostName as NSString
        if ckRecord[CloudKitSchema.Field.firstSeen] == nil {
            ckRecord[CloudKitSchema.Field.firstSeen] = record.lastSeen as NSDate
        }
        ckRecord[CloudKitSchema.Field.lastSeen] = record.lastSeen as NSDate
        ckRecord[CloudKitSchema.Field.removed] = NSNumber(value: record.removed)
        await save(ckRecord, context: "device upsert")
    }

    public func writeHeartbeat(_ record: RemoteDeviceRecord) async {
        let id = CKRecord.ID(
            recordName: CloudKitSchema.deviceActivityRecordName(for: record.deviceID)
        )
        let ckRecord = CKRecord(
            recordType: CloudKitSchema.RecordType.deviceActivity,
            recordID: id
        )
        ckRecord[CloudKitSchema.Field.deviceID] = record.deviceID as NSString
        ckRecord[CloudKitSchema.Field.deviceName] = record.deviceName as NSString
        ckRecord[CloudKitSchema.Field.timestamp] = record.lastSeen as NSDate
        ckRecord[CloudKitSchema.Field.isActive] = NSNumber(value: record.isActive)
        await save(ckRecord, context: "heartbeat")
    }

    public func fetchRemoteDevices() async -> [RemoteDeviceRecord] {
        let devices = await fetchAll(recordType: CloudKitSchema.RecordType.device)
        guard !devices.isEmpty else { return [] }
        let activity = await fetchAll(
            recordType: CloudKitSchema.RecordType.deviceActivity
        )
        let activityByID = Dictionary(
            activity.compactMap { record -> (String, CKRecord)? in
                guard let deviceID = record[CloudKitSchema.Field.deviceID] as? String
                else { return nil }
                return (deviceID, record)
            },
            uniquingKeysWith: { lhs, rhs in
                let lTime = lhs[CloudKitSchema.Field.timestamp] as? Date ?? .distantPast
                let rTime = rhs[CloudKitSchema.Field.timestamp] as? Date ?? .distantPast
                return rTime > lTime ? rhs : lhs
            }
        )
        return devices.compactMap { device in
            guard let deviceID = device[CloudKitSchema.Field.deviceID] as? String
            else { return nil }
            let name = device[CloudKitSchema.Field.deviceName] as? String ?? deviceID
            let removed = (device[CloudKitSchema.Field.removed] as? Int ?? 0) != 0
            let heartbeat = activityByID[deviceID]
            let lastSeen = heartbeat?[CloudKitSchema.Field.timestamp] as? Date
                ?? device[CloudKitSchema.Field.lastSeen] as? Date
                ?? .distantPast
            let isActive = (heartbeat?[CloudKitSchema.Field.isActive] as? Int ?? 0) != 0
            return RemoteDeviceRecord(
                deviceID: deviceID,
                deviceName: name,
                lastSeen: lastSeen,
                isActive: isActive,
                removed: removed
            )
        }
    }

    private func fetchAll(recordType: String) async -> [CKRecord] {
        let query = CKQuery(
            recordType: recordType,
            predicate: NSPredicate(value: true)
        )
        do {
            let (results, _) = try await database.records(matching: query)
            return results.compactMap { try? $0.1.get() }
        } catch {
            // A query against a record type that isn't marked queryable (the
            // schema hasn't been promoted to production, or its queryable index
            // is missing) fails persistently with an actionable CKError — surface
            // that at `.error` so a misconfigured schema is debuggable. Transient
            // outages stay quiet at `.debug`, since device awareness soft-fails.
            if let ckError = error as? CKError, Self.isSchemaMisconfiguration(ckError) {
                deviceStoreLogger.error(
                    """
                    fetch \(recordType, privacy: .public) returned no devices — is this \
                    record type marked queryable in the CloudKit schema? \
                    \(error.localizedDescription, privacy: .public)
                    """
                )
            } else {
                deviceStoreLogger.debug(
                    "fetch \(recordType) failed: \(error.localizedDescription)"
                )
            }
            return []
        }
    }

    /// Classifies a CloudKit query failure as a persistent schema problem
    /// (record type not queryable, or not yet provisioned) rather than a
    /// transient outage, so only the actionable case is logged at `.error`.
    private static func isSchemaMisconfiguration(_ error: CKError) -> Bool {
        switch error.code {
        case .invalidArguments, .unknownItem:
            true
        default:
            false
        }
    }

    private func save(_ record: CKRecord, context: String) async {
        do {
            _ = try await database.save(record)
        } catch {
            deviceStoreLogger.debug("\(context) save failed: \(error.localizedDescription)")
        }
    }
}
