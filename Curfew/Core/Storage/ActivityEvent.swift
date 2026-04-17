import Foundation

/// One entry in Curfew's activity log.
///
/// The log is the source of truth for the "This Week" retrospective, CSV
/// export, and (later) device-attributed insights. Schema is deliberately
/// flat so it maps cleanly onto a single SQLite table and can be extended
/// without migrations — optional fields (`minutesValue`, `note`) cover the
/// per-kind payloads without a full type hierarchy.
///
/// `gateKind` exists so the same table can host future reflection gates
/// (morning intent, midday check-in, evening retrospective) without a schema
/// split. Every event written in v0.1 uses `GateKind.curfew`; downstream
/// aggregators filter on this field.
public struct ActivityEvent: Equatable, Hashable {
    /// Stable identifier. Defaults to a fresh UUID when omitted; preserved
    /// across read/write so sync dedup (post-v0.1) has a primary key.
    public let id: UUID

    /// Wall-clock moment the event occurred. Stored as the SQLite
    /// `timestamp` column and used as the rollup bucketing key.
    public let timestamp: Date

    /// Gate family that produced the event. Pass one of ``GateKind``'s
    /// constants so spelling stays consistent across recorders.
    public let gateKind: String

    /// Discriminant — see ``ActivityEventKind``. Determines how
    /// `minutesValue` and `note` should be interpreted.
    public let kind: ActivityEventKind

    /// Numeric payload whose meaning depends on `kind`:
    /// - `.extensionGranted` / `.overrideGranted`: minutes granted
    /// - `.warningEscalated`: minutes remaining at escalation
    /// - otherwise: `nil`
    public let minutesValue: Int?

    /// Free-form text payload. Used for override reasons and future
    /// reflection responses. `nil` when not applicable.
    public let note: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        gateKind: String,
        kind: ActivityEventKind,
        minutesValue: Int?,
        note: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.gateKind = gateKind
        self.kind = kind
        self.minutesValue = minutesValue
        self.note = note
    }
}

/// Stable identifiers for gate families. The raw strings appear in the
/// SQLite column, CSV exports, and MCP tool responses — never rename
/// without a migration plan. Future reflection gates (morning intent,
/// midday check-in, evening retrospective) each add a case here.
public enum GateKind {
    /// End-of-day curfew gate. The only gate family that ships in v0.1.
    public static let curfew = "curfew"
}

/// Discriminant for ``ActivityEvent``. Raw `String` values are the stable
/// wire format (SQLite, CSV, MCP tool responses). Do not rename cases
/// without a migration plan — existing rows on user machines carry the
/// raw strings verbatim.
public enum ActivityEventKind: String, Equatable, Hashable, CaseIterable {
    /// First tick after the daily unlock time — the working window began.
    case sessionStarted = "session_started"

    /// Working window ended because curfew lockout began.
    case sessionEnded = "session_ended"

    /// A warning stage fired (T-30 / T-15 / T-5 / T-2 / T-1). The stage
    /// label lives in the event's `note` field and the minutes remaining
    /// at that moment live in `minutesValue`.
    case warningEscalated = "warning_escalated"

    /// Lockout overlay began displaying — the user is now locked out.
    case lockoutStarted = "lockout_started"

    /// Lockout ended (natural unlock or override).
    case lockoutEnded = "lockout_ended"

    /// An extension was granted via the warning-phase hold-to-confirm
    /// button. `minutesValue` carries the minutes added; no `note`.
    case extensionGranted = "extension_granted"

    /// An override was granted via the "Convince Me" lockout flow.
    /// `minutesValue` carries the granted duration; `note` carries the
    /// user's typed justification verbatim.
    case overrideGranted = "override_granted"

    /// A scheduled day-off boundary was crossed.
    case dayOff = "day_off"
}
