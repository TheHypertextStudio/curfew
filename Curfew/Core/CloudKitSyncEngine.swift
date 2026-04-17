import CloudKit
import Combine
import Foundation
import OSLog

private let syncLogger = Logger(subsystem: "studio.hypertext.curfew", category: "cloudkit-sync")

/// Syncs `CurfewSettings` across the user's devices via CloudKit private database.
///
/// Lifecycle: call `start()` once after the app model is ready and both
/// `featureFlags.cloudSyncEnabled` and `licenseGate.isProUnlocked` are true.
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
final class CloudKitSyncEngine {
    /// Called on the main actor when a newer settings payload arrives from
    /// the cloud. The app model applies it and persists locally.
    var onSettingsReceived: ((CurfewSettings) -> Void)?

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

    nonisolated init(
        containerID: String = "iCloud.studio.hypertext.curfew"
    ) {
        self.containerID = containerID
    }

    private var resolvedContainer: CKContainer {
        if let existing = container { return existing }
        let new = CKContainer(identifier: containerID)
        container = new
        return new
    }

    // MARK: - Lifecycle

    func start(localSettings: CurfewSettings, localModifiedAt: Date) {
        guard !active else { return }
        active = true
        syncLogger.info("CloudKit sync starting")
        Task {
            await pull(localSettings: localSettings, localModifiedAt: localModifiedAt)
        }
    }

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

    // MARK: - Private

    private func pull(localSettings: CurfewSettings, localModifiedAt: Date) async {
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
                return
            }
            let remote = try decoder.decode(CurfewSettings.self, from: data)
            syncLogger.info("CloudKit pull: applying remote settings (modified \(remoteModified))")
            onSettingsReceived?(remote)
        } catch let error as CKError where error.isExpectedAbsence {
            // No record yet — push local settings to seed the cloud copy.
            syncLogger.info("CloudKit pull: no remote record, seeding from local")
            await save(settings: localSettings, modifiedAt: localModifiedAt)
        } catch {
            syncLogger.error("CloudKit pull failed: \(error.localizedDescription)")
        }
    }

    private func save(settings: CurfewSettings, modifiedAt: Date) async {
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
        } catch let error as CKError where error.isExpectedAbsence {
            syncLogger.info("CloudKit push skipped: iCloud not available")
        } catch {
            syncLogger.error("CloudKit push failed: \(error.localizedDescription)")
        }
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
