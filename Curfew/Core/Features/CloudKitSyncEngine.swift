import CloudKit
import CurfewKit
import Foundation
import Observation
import OSLog

private let syncLogger = Logger(subsystem: "studio.hypertext.curfew", category: "cloudkit-sync")

/// Observable status for CloudKit sync operations. Surfaced in
/// Settings → Devices so users can see when their schedule last synced
/// and whether the last attempt failed.
enum CloudKitSyncStatus: Equatable {
    /// No sync activity and no recorded success or failure.
    case idle
    /// A push or pull is in flight.
    case syncing
    /// Last sync completed successfully at the associated date.
    case synced(date: Date)
    /// Last sync attempt failed with the associated human-readable message.
    case failed(message: String)
    /// iCloud not authenticated, container not provisioned, or network
    /// unavailable — expected on first launch and offline.
    case unavailable
}

/// Syncs `CurfewSettings` across the user's devices via CloudKit private database.
///
/// Lifecycle: call `start()` once after the app model is ready and both
/// `featureFlags.cloudSyncEnabled` and `licenseGate.isPlusUnlocked` are true.
/// Call `stop()` when either condition becomes false.
///
/// Conflict resolution: last-write-wins based on `modifiedAt`. This is
/// intentionally simple for v0.1 — the user edits settings on one device
/// at a time in the typical case.
///
/// The CloudKit container (`iCloud.studio.hypertext.curfew`) must be
/// provisioned via App Store Connect before sync is live. The engine handles
/// `notAuthenticated`, `networkUnavailable`, and missing-container errors
/// gracefully so the app stays functional on first launch.
@MainActor
@Observable
final class CloudKitSyncEngine {
    /// Called on the main actor when a newer settings payload arrives from
    /// the cloud. The app model applies it and persists locally.
    @ObservationIgnored var onSettingsReceived: ((CurfewSettings) -> Void)?

    /// Current sync state. Updates on every push/pull attempt so
    /// Settings → Devices can show last-synced time and failure details.
    private(set) var syncStatus: CloudKitSyncStatus = .idle

    // CKContainer is created lazily in start() to avoid calling it off the
    // main thread — nonisolated init runs as a default argument before
    // @MainActor isolation is established, which trips libMainThreadChecker.
    private var container: CKContainer?
    private let containerID: String
    private var active = false
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Deterministic record ID — one settings record per iCloud account.
    private static let recordType = "Settings"
    private static let recordName = "curfew-settings-v1"
    private static let payloadKey = "payload"
    private static let modifiedKey = "modifiedAt"

    /// Creates a sync engine targeting `containerID` on the main actor.
    init(
        containerID: String? = nil
    ) {
        self.containerID = containerID ?? CloudKitSchema.containerID
    }

    private var resolvedContainer: CKContainer {
        if let existing = container {
            return existing
        }
        let new = CKContainer(identifier: containerID)
        container = new
        return new
    }

    // MARK: - Lifecycle

    /// Arms the engine. Kicks off the initial settings pull and
    /// registers the database-level subscription so subsequent remote
    /// changes arrive via silent push. Idempotent — repeat calls while
    /// already active no-op.
    func start(localSettings: CurfewSettings, localModifiedAt: Date) {
        guard !active else { return }
        active = true
        syncLogger.info("CloudKit sync starting")
        Task {
            await pull(localSettings: localSettings, localModifiedAt: localModifiedAt)
            await registerDatabaseSubscriptionIfNeeded()
        }
    }

    /// Creates a single `CKDatabaseSubscription` so remote record changes
    /// arrive via silent APS push. Idempotent — subscriptions have
    /// deterministic IDs (`CloudKitSchema.databaseSubscriptionID`); a
    /// second save against the same ID returns a benign
    /// `.serverRecordChanged` we swallow.
    ///
    /// On receipt of a push the app model calls `pullAll(localSettings:…)`
    /// — there's no fine-grained per-record dispatch yet; we re-pull the
    /// settings record and let `DeviceRegistry` observe its own heartbeats
    /// lazily.
    private func registerDatabaseSubscriptionIfNeeded() async {
        let subscription = CKDatabaseSubscription(
            subscriptionID: CloudKitSchema.databaseSubscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await resolvedContainer.privateCloudDatabase.save(subscription)
            syncLogger.info("CloudKit database subscription registered")
        } catch let error as CKError
            where error.code == .serverRejectedRequest
            || error.code == .unknownItem
            || error.isExpectedAbsence {
            // Most common benign case: subscription already exists. The
            // `serverRejectedRequest` code covers "subscription with that
            // identifier already present" in current CloudKit versions.
            syncLogger.debug("database subscription already present")
        } catch {
            syncLogger.error(
                "subscription registration failed: \(error.localizedDescription)"
            )
        }
    }

    /// Disarms the engine. Future `push`/`pull` calls no-op until a
    /// subsequent `start` re-activates. Subscriptions stay registered —
    /// removing them on every license flip would churn CloudKit quota.
    func stop() {
        active = false
        syncLogger.info("CloudKit sync stopped")
    }

    // MARK: - Push

    /// Encodes `settings` and saves to the private CloudKit database.
    /// Silently no-ops when not active or when CloudKit is unavailable.
    func push(_ settings: CurfewSettings, modifiedAt: Date = Date()) {
        guard active else { return }
        Task {
            await save(settings: settings, modifiedAt: modifiedAt)
        }
    }

    /// Callback fired when a pulled `LockoutState` record carries a
    /// non-empty `warningStagesFired` set. The app model uses this to
    /// seed its local suppression set on launch so a Mac restarting
    /// mid-day doesn't re-fire stages that already fired on this or
    /// another Mac today.
    var onLockoutStateReceived: ((LockoutStateSnapshot) -> Void)?

    /// Writes the shared `LockoutState` record so devices joining the
    /// warning phase mid-escalation can align their stage baseline with
    /// whichever Mac entered warning first.
    ///
    /// Rolling keys: passing `warningPhaseStarted = nil` clears the field
    /// (e.g. when the user drops out of warning because an extension was
    /// granted). The record is kept alive — CloudKit quota penalises
    /// create/delete churn more than overwrite churn.
    func pushLockoutState(
        phase: String,
        warningPhaseStarted: Date?,
        lockedAt: Date?,
        unlocksAt: Date?,
        warningStagesFired: Set<String> = []
    ) {
        guard active else { return }
        Task {
            await saveLockoutState(
                phase: phase,
                warningPhaseStarted: warningPhaseStarted,
                lockedAt: lockedAt,
                unlocksAt: unlocksAt,
                warningStagesFired: warningStagesFired
            )
        }
    }

    /// Fetches the shared `LockoutState` record and surfaces its
    /// `warningStagesFired` set via `onLockoutStateReceived`. Called on
    /// sync start so a device that was offline when earlier stages
    /// fired learns about them before firing its own duplicates.
    func pullLockoutState() {
        guard active else { return }
        Task {
            await loadLockoutState()
        }
    }

    private func saveLockoutState(
        phase: String,
        warningPhaseStarted: Date?,
        lockedAt: Date?,
        unlocksAt: Date?,
        warningStagesFired: Set<String>
    ) async {
        let database = resolvedContainer.privateCloudDatabase
        let id = CKRecord.ID(recordName: CloudKitSchema.lockoutStateRecordName)
        do {
            // Fetch-then-modify so CloudKit's server change tag stays
            // coherent — avoids `.serverRecordChanged` on concurrent
            // writers.
            let record: CKRecord
                = if let existing = try? await database.record(for: id) {
                existing
            } else {
                CKRecord(
                    recordType: CloudKitSchema.RecordType.lockoutState,
                    recordID: id
                )
            }
            record[CloudKitSchema.Field.phase] = phase as NSString
            record[CloudKitSchema.Field.warningPhaseStarted] = warningPhaseStarted as NSDate?
            record[CloudKitSchema.Field.lockedAt] = lockedAt as NSDate?
            record[CloudKitSchema.Field.unlocksAt] = unlocksAt as NSDate?
            record[CloudKitSchema.Field.modifiedAt] = Date() as NSDate
            record[CloudKitSchema.Field.warningStagesFired]
                = warningStagesFired.sorted() as NSArray
            _ = try await database.save(record)
        } catch let error as CKError where error.isExpectedAbsence {
            syncLogger.debug("lockout-state save skipped: CloudKit unavailable")
        } catch {
            syncLogger.error("lockout-state save failed: \(error.localizedDescription)")
        }
    }

    private func loadLockoutState() async {
        let database = resolvedContainer.privateCloudDatabase
        let id = CKRecord.ID(recordName: CloudKitSchema.lockoutStateRecordName)
        do {
            let record = try await database.record(for: id)
            let phase = record[CloudKitSchema.Field.phase] as? String
            let stages = record[CloudKitSchema.Field.warningStagesFired] as? [String] ?? []
            let modifiedAt = record[CloudKitSchema.Field.modifiedAt] as? Date ?? .distantPast
            let snapshot = LockoutStateSnapshot(
                phase: phase,
                warningStagesFired: Set(stages),
                modifiedAt: modifiedAt
            )
            await MainActor.run {
                onLockoutStateReceived?(snapshot)
            }
        } catch let error as CKError where error.isExpectedAbsence {
            syncLogger.debug("lockout-state pull skipped: CloudKit unavailable")
        } catch {
            syncLogger.error("lockout-state pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func pull(localSettings: CurfewSettings, localModifiedAt: Date) async {
        await MainActor.run { syncStatus = .syncing }
        let database = resolvedContainer.privateCloudDatabase
        let id = CKRecord.ID(recordName: Self.recordName)
        do {
            let record = try await database.record(for: id)
            guard
                let data = record[Self.payloadKey] as? Data,
                let remoteModified = record[Self.modifiedKey] as? Date,
                remoteModified > localModifiedAt
            else {
                syncLogger.info("CloudKit pull: local is up to date")
                await MainActor.run { syncStatus = .synced(date: Date()) }
                return
            }
            let remote = try decoder.decode(CurfewSettings.self, from: data)
            syncLogger.info("CloudKit pull: applying remote settings (modified \(remoteModified))")
            await MainActor.run {
                onSettingsReceived?(remote)
                syncStatus = .synced(date: Date())
            }
        } catch let error as CKError where error.isExpectedAbsence {
            // No record yet — push local settings to seed the cloud copy.
            syncLogger.info("CloudKit pull: no remote record, seeding from local")
            await save(settings: localSettings, modifiedAt: localModifiedAt)
        } catch {
            syncLogger.error("CloudKit pull failed: \(error.localizedDescription)")
            await MainActor.run { syncStatus = .failed(message: error.localizedDescription) }
        }
    }

    private func save(settings: CurfewSettings, modifiedAt: Date) async {
        await MainActor.run { syncStatus = .syncing }
        let database = resolvedContainer.privateCloudDatabase
        let id = CKRecord.ID(recordName: Self.recordName)
        do {
            let record: CKRecord
                // Fetch-then-modify to avoid overwriting server change tags.
                = if let existing = try? await database.record(for: id) {
                existing
            } else {
                CKRecord(recordType: Self.recordType, recordID: id)
            }
            record[Self.payloadKey] = try encoder.encode(settings) as NSData
            record[Self.modifiedKey] = modifiedAt as NSDate
            try await database.save(record)
            syncLogger.info("CloudKit push: saved settings at \(modifiedAt)")
            await MainActor.run { syncStatus = .synced(date: Date()) }
        } catch let error as CKError where error.isExpectedAbsence {
            syncLogger.info("CloudKit push skipped: iCloud not available")
            await MainActor.run { syncStatus = .unavailable }
        } catch {
            syncLogger.error("CloudKit push failed: \(error.localizedDescription)")
            await MainActor.run { syncStatus = .failed(message: error.localizedDescription) }
        }
    }
}

/// Plain-value snapshot of the shared `LockoutState` CKRecord.
/// Crosses the `CloudKitSyncEngine` → `CurfewAppModel` boundary so the
/// app model doesn't need to know about `CKRecord` internals.
public struct LockoutStateSnapshot: Equatable, Sendable {
    /// Tokenised enforcement phase ("working", "warning", "locked",
    /// "day_off"), or `nil` when the record is absent.
    public let phase: String?
    /// Warning-stage tokens that have already fired today somewhere on
    /// this iCloud account. Consumed by `WarningNotificationManager`
    /// to suppress cross-device duplicate alarms.
    public let warningStagesFired: Set<String>
    /// Server-last-modified timestamp; consumers ignore snapshots older
    /// than their own local view.
    public let modifiedAt: Date

    /// Memberwise initialiser. Kept explicit so the struct stays
    /// `public` with a stable documented API surface.
    public init(phase: String?, warningStagesFired: Set<String>, modifiedAt: Date) {
        self.phase = phase
        self.warningStagesFired = warningStagesFired
        self.modifiedAt = modifiedAt
    }
}

private extension CKError {
    /// True for errors that are expected/recoverable rather than bugs:
    /// not authenticated, network unavailable, quota exceeded, or the
    /// CloudKit container not yet provisioned.
    var isExpectedAbsence: Bool {
        switch code {
        case .notAuthenticated, .networkUnavailable, .networkFailure,
             .serviceUnavailable, .requestRateLimited, .unknownItem,
             .zoneNotFound, .userDeletedZone:
            true
        default:
            false
        }
    }
}
