import CloudKit
import CurfewKit
import Foundation

/// Canonical CloudKit schema descriptors for Curfew's private database.
///
/// Collected here so every record-type string, field key, and deterministic
/// record-name constant lives in one place. Typos that diverge the app's
/// writer from the widget's reader produce silent "no data" failures that
/// are hard to debug after the fact.
///
/// Schema evolution (v0.1 → v0.2):
///
/// v0.1 used a single `Settings` record with a JSON-encoded `CurfewSettings`
/// payload. v0.2 keeps that record for backward compatibility while adding
/// device-awareness records (`Device`, `DeviceActivity`) and a dedicated
/// `LockoutState` record for warning handoff. The legacy `Settings` record
/// remains the source of truth for `schedule`, `warningIntervals`, and
/// the Plus gate flags — peeling them into their own records is a later
/// migration that can land independently.
public enum CloudKitSchema {
    // MARK: - Container

    /// The private-database container identifier, matching the iCloud
    /// entitlement in `Curfew-Release.entitlements`. Single source of truth
    /// so the sync engine and the device store target the same container.
    public static let containerID = "iCloud.studio.hypertext.curfew"

    // MARK: - Record types

    /// The four CKRecord types Curfew writes into the user's private
    /// CloudKit database. Namespace-only — each case is a static string
    /// constant, not a Swift enum case, so CKRecord APIs receive the
    /// stable on-the-wire names directly.
    public enum RecordType {
        /// Single-record JSON-encoded `CurfewSettings` blob. v0.1 shape;
        /// retained for back-compat.
        public static let settings = "Settings"

        /// Per-device registration row. One record per physical Mac
        /// keyed on `Device.recordName` (below). Tracks hostname, pretty
        /// name, first-seen / last-seen timestamps, and a soft-delete
        /// flag so removed devices can re-register without a conflict.
        public static let device = "Device"

        /// Per-device heartbeat. Written every 60 s while the user is
        /// active on that device; consumed by active-device detection
        /// and the cross-device work-hour aggregator.
        public static let deviceActivity = "DeviceActivity"

        /// Live lockout / warning state for multi-device handoff. A
        /// single record shared across devices; whichever device first
        /// enters the warning window writes `warningPhaseStarted` so
        /// other devices joining mid-escalation land at the correct
        /// stage rather than restarting at T-30.
        public static let lockoutState = "LockoutState"
    }

    // MARK: - Deterministic record names

    /// Single-record settings; v0.1 name preserved for migration.
    public static let settingsRecordName = "curfew-settings-v1"

    /// Single shared lockout-state record. Deterministic name so every
    /// device's reader and writer agree on the key.
    public static let lockoutStateRecordName = "lockout-state-v1"

    /// Per-device record name derived from the device's identifier. Stable
    /// across app launches (tied to hardware UUID) so a restart doesn't
    /// create a duplicate Device row.
    public static func deviceRecordName(for deviceID: String) -> String {
        "device-\(deviceID)"
    }

    /// Per-device activity record name. One record per device; the record
    /// is overwritten every heartbeat rather than appended to, so quota
    /// usage stays bounded regardless of uptime.
    public static func deviceActivityRecordName(for deviceID: String) -> String {
        "device-activity-\(deviceID)"
    }

    // MARK: - Field keys

    /// Stable on-the-wire field names keyed by record type. Declaring
    /// them centrally keeps writers and readers in sync — a typo here
    /// is the kind of bug that produces silent "no data" failures.
    public enum Field {
        // Settings (v0.1, retained)

        /// `Data` — JSON-encoded `CurfewSettings` blob (v0.1 shape).
        public static let payload = "payload"
        /// `Date` — last-write-wins conflict-resolution timestamp.
        public static let modifiedAt = "modifiedAt"

        // Device

        /// `String` — stable per-Mac identifier (from `IOPlatformUUID`).
        public static let deviceID = "deviceID"
        /// `String` — human-readable Mac name, matching Sharing.
        public static let deviceName = "deviceName"
        /// `String` — `ProcessInfo.hostName` for diagnostic display.
        public static let hostname = "hostname"
        /// `Date` — when this device first registered on the account.
        public static let firstSeen = "firstSeen"
        /// `Date` — most recent heartbeat observed from this device.
        public static let lastSeen = "lastSeen"
        /// `Bool` — soft-delete flag; survives `remove device` so a
        /// re-launching Mac can re-register without a conflict.
        public static let removed = "removed"

        // DeviceActivity

        /// `Date` — heartbeat moment from the emitting device.
        public static let timestamp = "timestamp"
        /// `Bool` — whether the user was actively using this Mac at the
        /// heartbeat moment (false during `IdleWatcher.isIdle`).
        public static let isActive = "isActive"
        /// `Int` — minutes of active work today on the emitting device.
        /// Aggregated across devices by `WorkTimeAggregator`.
        public static let workedMinutesToday = "workedMinutesToday"

        // LockoutState

        /// `String` — tokenised enforcement phase ("working", "warning",
        /// "locked", "day_off"). Mirrors `CurfewKit.phaseName(_:)`.
        public static let phase = "phase"
        /// `Date?` — when the current warning phase started, so devices
        /// joining mid-escalation align their baseline.
        public static let warningPhaseStarted = "warningPhaseStarted"
        /// `Date?` — lock-start moment when phase is `.locked`.
        public static let lockedAt = "lockedAt"
        /// `Date?` — expected unlock moment when phase is `.locked`.
        public static let unlocksAt = "unlocksAt"
        /// `[String]` of warning-stage tokens ("T-30", "T-15", …) that
        /// have fired today across any device on this account. Consumed
        /// by `WarningNotificationManager` to suppress cross-device
        /// duplicate alarms.
        public static let warningStagesFired = "warningStagesFired"
    }

    // MARK: - Subscription IDs

    /// Deterministic subscription ID so `register` is idempotent. Attempting
    /// to create a second subscription with the same ID returns a benign
    /// `.serverRecordChanged` that we ignore.
    public static let databaseSubscriptionID = "curfew-database-v1"
}
