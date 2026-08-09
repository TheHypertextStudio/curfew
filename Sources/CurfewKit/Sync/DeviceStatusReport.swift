import CryptoKit
import Foundation

/// One device-status body, ready to be published to a curfew-sync coordinator.
///
/// **Shape authority.** Every key, every value format, and every constraint
/// below is copied from `curfew-protocols/schemas/device.json`
/// → `#/definitions/DeviceStatusSnapshot`. Nothing here is invented. If a
/// future need cannot be expressed in that definition, the fix is a change to
/// curfew-protocols and a regenerated schema, never a field coined here — the
/// three-repo rule exists because a field the device sends and the coordinator
/// has never heard of is worse than no field at all.
///
/// `DeviceStatusSnapshot` is the right definition rather than
/// `sync.json#/definitions/DeviceStatusPublication`, which describes the same
/// state as it appears on the *device socket*. That one additionally requires
/// `type: "status"` and a `cursor`, and a cursor is a coordinator-assigned
/// stream position — a device has no way to mint one. The publication frame is
/// what the coordinator emits; the snapshot is what a device reports.
///
/// **Privacy.** The eight keys below are the whole of what leaves the machine.
/// There is no representation here for a camera frame, a window title, an
/// application name, a URL, a document, or any user-authored text, and the type
/// admits none: every field is a scalar the enforcement engine already computed
/// for its own purposes. This mirrors the rule
/// `CurfewAppModel+AuditPresence.swift` established for the audit log — derived
/// verdicts leave, observations do not.
///
/// Notably absent: presence. ``PresenceState`` has no home in
/// `DeviceStatusSnapshot`, so a Curfew device cannot report to a coordinator
/// whether a person is at the machine. That is a gap in curfew-protocols, not
/// something to paper over locally — see `Documentation/curfew-sync-status.md`.
public struct DeviceStatusReport: Equatable {
    /// The exact key set `DeviceStatusSnapshot` defines.
    ///
    /// Public because it is the contract, and a test that asserts the encoder's
    /// output against a set it derives from the encoder itself would prove
    /// nothing. This constant is transcribed from the schema by hand and is the
    /// thing worth diffing when curfew-protocols moves.
    public static let schemaKeys: Set<String> = [
        "deviceId",
        "phase",
        "timeZone",
        "scheduleDigest",
        "statusVersion",
        "observedAt",
        "nextTransitionAt",
        "activeLockoutEndsAt"
    ]

    /// The six keys the schema marks `required`. The remaining two are
    /// nullable, and this encoder always emits them explicitly as `null` rather
    /// than omitting them, so the body's key set never varies with state.
    public static let requiredSchemaKeys: Set<String> = [
        "deviceId",
        "phase",
        "timeZone",
        "scheduleDigest",
        "statusVersion",
        "observedAt"
    ]

    /// Schema `CanonicalUUID`: lowercase, version nibble 1–8, RFC 4122 variant.
    public static let deviceIDPattern =
        "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

    /// Schema `UTCInstant`: RFC 3339 with a literal `Z`, never a numeric offset.
    public static let instantPattern =
        "^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T"
            + "([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]{1,9})?Z$"

    /// Schema `scheduleDigest`: 43 unpadded base64url characters — one SHA-256.
    public static let scheduleDigestPattern = "^[A-Za-z0-9_-]{43}$"

    /// Schema `timeZone`: an IANA identifier with at least one `/`.
    public static let timeZonePattern = "^[A-Za-z_+-]+(?:/[A-Za-z0-9_+-]+)+$"

    /// This device's stable identifier. Minted once per install and persisted
    /// in settings; never derived from hardware, so it cannot be correlated
    /// with anything outside Curfew.
    public var deviceID: String

    /// The enforcement phase this device is in.
    public var phase: EnforcementPhase

    /// IANA timezone identifier, so a coordinator can render another Mac's
    /// deadline in its own local time.
    public var timeZone: String

    /// Digest of the local schedule. Lets a coordinator tell "this device is
    /// running the schedule I think it is" without ever receiving the schedule.
    public var scheduleDigest: String

    /// The monotonic counter the coordinator's staleness guard compares
    /// against. Strictly increasing per device across the install's whole
    /// lifetime, including relaunches — see ``DeviceStatusVersionCounter``.
    public var statusVersion: Int

    /// When this state was observed.
    public var observedAt: Date

    /// When the phase is next expected to change, or `nil` on a day off.
    public var nextTransitionAt: Date?

    /// When the running lockout ends, or `nil` when no lockout is running.
    public var activeLockoutEndsAt: Date?

    /// Memberwise initialiser.
    public init(
        deviceID: String,
        phase: EnforcementPhase,
        timeZone: String,
        scheduleDigest: String,
        statusVersion: Int,
        observedAt: Date,
        nextTransitionAt: Date?,
        activeLockoutEndsAt: Date?
    ) {
        self.deviceID = deviceID
        self.phase = phase
        self.timeZone = timeZone
        self.scheduleDigest = scheduleDigest
        self.statusVersion = statusVersion
        self.observedAt = observedAt
        self.nextTransitionAt = nextTransitionAt
        self.activeLockoutEndsAt = activeLockoutEndsAt
    }

    /// The JSON body, with keys and value formats exactly as
    /// `DeviceStatusSnapshot` defines them.
    ///
    /// Written as an explicit dictionary rather than a `Codable` conformance so
    /// the wire key set is legible on one screen and a rename shows up as a
    /// diff on the line that produces it. `sortedKeys` keeps the bytes
    /// deterministic, which makes the payload test an equality check rather
    /// than a parse-and-compare.
    ///
    /// - Throws: Only if `JSONSerialization` rejects the object, which it
    ///   cannot for a dictionary of strings, integers, and `NSNull`.
    public func encodedBody() throws -> Data {
        let body: [String: Any] = [
            "deviceId": deviceID,
            "phase": AuditTokens.phase(phase),
            "timeZone": timeZone,
            "scheduleDigest": scheduleDigest,
            "statusVersion": statusVersion,
            "observedAt": Self.instant(observedAt),
            "nextTransitionAt": Self.instantOrNull(nextTransitionAt),
            "activeLockoutEndsAt": Self.instantOrNull(activeLockoutEndsAt)
        ]
        // `sortedKeys` makes the bytes deterministic. `withoutEscapingSlashes`
        // keeps `America/Los_Angeles` readable on the wire: an escaped solidus
        // is legal JSON and every parser accepts it, but it makes a captured
        // request harder to read for no benefit.
        return try JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Whether every field satisfies the schema's constraints.
    ///
    /// Checked before a report is ever handed to a transport. A malformed body
    /// would be rejected by the coordinator anyway, but failing here means a
    /// device with, say, an unset identifier stays quiet instead of retrying a
    /// guaranteed-400 every heartbeat forever.
    public var isWellFormed: Bool {
        deviceID.matches(Self.deviceIDPattern)
            && timeZone.matches(Self.timeZonePattern)
            && scheduleDigest.matches(Self.scheduleDigestPattern)
            && statusVersion >= 0
    }

    /// The schema-shaped digest of `schedule`: unpadded base64url SHA-256 over
    /// ``AuditScheduleSummary/canonical(_:)``.
    ///
    /// Deliberately hashes the same canonical string the audit summary does, so a
    /// support conversation can line a coordinator's `scheduleDigest` up
    /// against a local audit record and know they describe one schedule. The
    /// encodings differ because the schema asks for 43 base64url characters and
    /// the audit format asks for 16 hex; the preimage is identical.
    public static func scheduleDigest(for schedule: WeeklySchedule) -> String {
        let hash = SHA256.hash(data: Data(AuditScheduleSummary.canonical(schedule).utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Formats `date` as a schema `UTCInstant` — RFC 3339, UTC, `Z`-suffixed,
    /// whole seconds.
    public static func instant(_ date: Date) -> String {
        instantFormatter.string(from: date)
    }

    private static func instantOrNull(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return instant(date)
    }

    /// Fixed to UTC and to `.withInternetDateTime` so the output can never
    /// acquire a numeric offset, which the schema's pattern rejects.
    private static let instantFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

private extension String {
    /// Whole-string match against `pattern`. The schema patterns are all
    /// anchored, so a range search is enough.
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
