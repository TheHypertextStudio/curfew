import CryptoKit
import Foundation

/// One device-status body, ready to be published to a curfew-sync coordinator.
///
/// **Shape authority.** Every key, every value format, and every constraint
/// below is copied from `curfew-protocols/schemas/sync.json`
/// → `#/definitions/DeviceStatusPublication`. Nothing here is invented. If a
/// future need cannot be expressed in that definition, the fix is a change to
/// curfew-protocols and a regenerated schema, never a field coined here — the
/// three-repo rule exists because a field the device sends and the coordinator
/// has never heard of is worse than no field at all.
///
/// `DeviceStatusPublication` is the right definition because it is literally
/// what the route parses: `curfew-sync/src/routes/device-status.ts` hands the
/// body of `POST /sync/status` to `parseDeviceStatusPublication`, which enforces
/// the definition's `required` list, its patterns, and `additionalProperties:
/// false`. `device.json#/definitions/DeviceStatusSnapshot` is the *response*
/// shape — what `GET /sync/status` hands a reader — and a body in that shape is
/// rejected with `400 {"error":"invalid_status_publication"}` for want of `type`
/// and `cursor`.
///
/// **Privacy.** The ten keys below are the whole of what leaves the machine.
/// There is no representation here for a camera frame, a window title, an
/// application name, a URL, a document, or any user-authored text, and the type
/// admits none: every field is a scalar the enforcement engine already computed
/// for its own purposes, a constant, or a digest of the other two. This mirrors
/// the rule `CurfewAppModel+AuditPresence.swift` established for the audit log —
/// derived verdicts leave, observations do not.
///
/// Notably absent: presence. ``PresenceState`` has no home in
/// `DeviceStatusPublication`, so a Curfew device cannot report to a coordinator
/// whether a person is at the machine. That is a gap in curfew-protocols, not
/// something to paper over locally — see `Documentation/curfew-sync-status.md`.
public struct DeviceStatusReport: Equatable {
    /// The exact key set `DeviceStatusPublication` defines.
    ///
    /// Public because it is the contract, and a test that asserts the encoder's
    /// output against a set it derives from the encoder itself would prove
    /// nothing. This constant is transcribed from the schema by hand and is the
    /// thing worth diffing when curfew-protocols moves.
    public static let schemaKeys: Set<String> = [
        "type",
        "cursor",
        "deviceId",
        "phase",
        "timeZone",
        "scheduleDigest",
        "statusVersion",
        "observedAt",
        "nextTransitionAt",
        "activeLockoutEndsAt"
    ]

    /// The eight keys the schema marks `required`. The remaining two are
    /// nullable, and this encoder always emits them explicitly as `null` rather
    /// than omitting them, so the body's key set never varies with state.
    public static let requiredSchemaKeys: Set<String> = [
        "type",
        "cursor",
        "deviceId",
        "phase",
        "timeZone",
        "scheduleDigest",
        "statusVersion",
        "observedAt"
    ]

    /// Schema `type`: a constant discriminating this frame from the other
    /// members of `sync.json`'s top-level `oneOf`.
    public static let frameType = "status"

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

    /// Schema `Cursor`: 22–128 base64url characters. The 43 characters
    /// ``cursor(deviceID:statusVersion:)`` produces sit inside that range.
    public static let cursorPattern = "^[A-Za-z0-9_-]{22,128}$"

    /// Domain-separation prefix for the cursor preimage. Present so this
    /// digest can never collide with ``scheduleDigest(for:)``, which hashes a
    /// different string for a different purpose with the same algorithm.
    private static let cursorDomain = "curfew.device-status.v1"

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

    /// This publication's schema `cursor`, derived rather than stored — see
    /// ``cursor(deviceID:statusVersion:)`` for why a device mints its own.
    public var cursor: String {
        Self.cursor(deviceID: deviceID, statusVersion: statusVersion)
    }

    /// Returns the schema-safe IANA identifier for a system time zone.
    ///
    /// Foundation reports a machine configured for UTC as `UTC` or `GMT` on
    /// some headless hosts. Both are tzdb aliases, but the shared protocol
    /// requires a regional identifier with a slash. `Etc/UTC` represents the
    /// same zone and satisfies that wire constraint. Other non-regional fixed
    /// offsets stay invalid because inventing a region would misstate the
    /// device's daylight-saving rules.
    public static func wireTimeZoneIdentifier(for timeZone: TimeZone) -> String {
        let identifier = timeZone.identifier
        if identifier.matches(Self.timeZonePattern) {
            return identifier
        }
        return timeZone.secondsFromGMT() == 0 ? "Etc/UTC" : identifier
    }

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
    /// `DeviceStatusPublication` defines them.
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
            "type": Self.frameType,
            "cursor": cursor,
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
            && cursor.matches(Self.cursorPattern)
            && statusVersion >= 0
    }

    /// The schema `cursor` for one publication: unpadded base64url SHA-256 over
    /// `"curfew.device-status.v1\n<deviceID>\n<statusVersion>"`.
    ///
    /// **Why a device may mint this at all.** Neither
    /// `sync.json#/definitions/Cursor` nor `POST /sync/status` requires a cursor
    /// the server issued. The definition is a bare string pattern —
    /// `^[A-Za-z0-9_-]{22,128}$` — with no issuer, no signature, and no
    /// registry; `parseDeviceStatusPublication` checks only that pattern; and
    /// the route stores `publication.cursor` verbatim on the `device_status` row
    /// without comparing it against anything it ever handed out. The only place
    /// a coordinator *does* mint one is the device socket, where
    /// `DeviceSocketWelcome.cursor` is a stream position a client echoes back as
    /// `DeviceSocketHello.resumeCursor`. On this HTTP path there is no such
    /// stream and no such handshake, so the cursor is the publisher's own name
    /// for the frame — which is why an HTTP-only device can publish at all.
    ///
    /// **Why derived rather than random.** A cursor that is a pure function of
    /// `(deviceID, statusVersion)` makes a publication idempotent by name: the
    /// same status re-sent carries the same cursor, so a coordinator that
    /// deduplicates by cursor sees one frame rather than two, and a support
    /// conversation can line a stored cursor up against the version that
    /// produced it. A random token would give up both properties in exchange for
    /// unlinkability the `deviceId` in the same body already forecloses. And
    /// because ``DeviceStatusVersionCounter`` never reissues a version and
    /// ``DeviceStatusReporter`` refuses to publish one twice, distinct
    /// publications from this device always carry distinct cursors.
    ///
    /// **Why a digest rather than the values themselves.** `deviceId` and
    /// `statusVersion` are already in the body, so hashing them hides nothing
    /// from the coordinator. It is a shape decision: SHA-256 lands inside the
    /// 22–128 window for every input, where `"<uuid>:<version>"` would be 38
    /// characters of a 36-character alphabet the pattern does not admit
    /// wholesale (a UUID's hyphens are fine, but nothing guarantees a future
    /// identifier's punctuation would be).
    public static func cursor(deviceID: String, statusVersion: Int) -> String {
        let preimage = "\(cursorDomain)\n\(deviceID)\n\(statusVersion)"
        return base64URL(SHA256.hash(data: Data(preimage.utf8)))
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
        base64URL(SHA256.hash(data: Data(AuditScheduleSummary.canonical(schedule).utf8)))
    }

    /// A SHA-256 as the 43 unpadded base64url characters every digest in these
    /// schemas is spelled with — `scheduleDigest`, `keyThumbprint`, and the
    /// cursor this file mints.
    ///
    /// The encoding itself lives in ``Base64URL``, so the assertion signer and
    /// this file cannot drift into two spellings of the same transformation.
    private static func base64URL(_ hash: SHA256Digest) -> String {
        Base64URL.encode(Data(hash))
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
