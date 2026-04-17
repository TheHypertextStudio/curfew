import CloudKit
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
/// the Pro gate flags — peeling them into their own records is a later
/// migration that can land independently.
public enum CloudKitSchema {
    // MARK: - Record types

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

    public enum Field {
        // Settings (v0.1, retained)
        public static let payload = "payload"
        public static let modifiedAt = "modifiedAt"

        // Device
        public static let deviceID = "deviceID"
        public static let deviceName = "deviceName"
        public static let hostname = "hostname"
        public static let firstSeen = "firstSeen"
        public static let lastSeen = "lastSeen"
        public static let removed = "removed"

        // DeviceActivity
        public static let timestamp = "timestamp"
        public static let isActive = "isActive"
        public static let workedMinutesToday = "workedMinutesToday"

        // LockoutState
        public static let phase = "phase"
        public static let warningPhaseStarted = "warningPhaseStarted"
        public static let lockedAt = "lockedAt"
        public static let unlocksAt = "unlocksAt"
    }

    // MARK: - Subscription IDs

    /// Deterministic subscription ID so `register` is idempotent. Attempting
    /// to create a second subscription with the same ID returns a benign
    /// `.serverRecordChanged` that we ignore.
    public static let databaseSubscriptionID = "curfew-database-v1"
}
