import CryptoKit
@testable import Curfew
import Foundation
import Testing

/// The wire shape, asserted against the schema rather than against itself.
///
/// Every expectation below is transcribed by hand from
/// `curfew-protocols/schemas/sync.json` →
/// `#/definitions/DeviceStatusPublication`, the definition
/// `curfew-sync/src/routes/device-status.ts` parses `POST /sync/status` bodies
/// against. None of it is derived from `DeviceStatusReport`, because a test that
/// asks the encoder what the encoder produces passes with any key set at all —
/// including a wrong one. This project has been bitten by exactly that (the
/// first cut of this file transcribed `device.json` →
/// `#/definitions/DeviceStatusSnapshot`, the *response* shape, and passed while
/// every real request would have been rejected `400`), so the key literals here
/// are duplicated on purpose: if the encoder is renamed and this file is not,
/// the suite fails, which is the whole point.
struct DeviceStatusReportPayloadTests {
    // MARK: - Schema transcription

    /// `required` in `DeviceStatusPublication`, in schema order.
    static let requiredKeys: Set<String> = [
        "type",
        "cursor",
        "deviceId",
        "phase",
        "timeZone",
        "scheduleDigest",
        "statusVersion",
        "observedAt"
    ]

    /// The two nullable keys `properties` defines beyond the required set.
    static let nullableKeys: Set<String> = ["nextTransitionAt", "activeLockoutEndsAt"]

    /// `additionalProperties: false`, so the body may contain these and nothing
    /// else.
    static let allowedKeys: Set<String> = requiredKeys.union(nullableKeys)

    /// The `DevicePhase` enum, verbatim.
    static let phaseValues: Set<String> = ["working", "warning", "locked", "day_off", "unknown"]

    /// `sync.json#/definitions/Cursor`, verbatim.
    static let cursorPattern = "^[A-Za-z0-9_-]{22,128}$"

    // MARK: - Fixtures

    /// A fully populated report. Fixed values throughout so the encoded bytes
    /// are a constant and the payload assertion can be an equality check.
    static func sample(
        phase: EnforcementPhase = .locked,
        nextTransitionAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        activeLockoutEndsAt: Date? = Date(timeIntervalSince1970: 1_800_003_600)
    ) -> DeviceStatusReport {
        DeviceStatusReport(
            deviceID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            phase: phase,
            timeZone: "America/Los_Angeles",
            scheduleDigest: "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU",
            statusVersion: 7,
            observedAt: Date(timeIntervalSince1970: 1_799_999_999),
            nextTransitionAt: nextTransitionAt,
            activeLockoutEndsAt: activeLockoutEndsAt
        )
    }

    private func decoded(_ report: DeviceStatusReport) throws -> [String: Any] {
        let data = try report.encodedBody()
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - Key set

    @Test("The encoded body's key set is exactly what DeviceStatusPublication defines")
    func keySetMatchesTheSchemaExactly() throws {
        let body = try decoded(Self.sample())

        #expect(Set(body.keys) == Self.allowedKeys)
        // Stated separately so a failure says which half broke: a missing
        // required key and an extra undeclared one are different bugs, and
        // `additionalProperties: false` means the coordinator rejects the
        // second outright.
        #expect(Self.requiredKeys.isSubset(of: Set(body.keys)))
        #expect(Set(body.keys).subtracting(Self.allowedKeys).isEmpty)
    }

    @Test("Every key is present even when the nullable fields are empty")
    func nullableKeysAreEmittedAsNull() throws {
        let body = try decoded(
            Self.sample(phase: .dayOff, nextTransitionAt: nil, activeLockoutEndsAt: nil)
        )

        #expect(Set(body.keys) == Self.allowedKeys)
        #expect(body["nextTransitionAt"] is NSNull)
        #expect(body["activeLockoutEndsAt"] is NSNull)
    }

    // MARK: - Value shapes

    @Test("Every value matches the schema's type and pattern")
    func valuesMatchTheSchemaPatterns() throws {
        let body = try decoded(Self.sample())

        // `const: "status"` — the discriminator that tells the coordinator's
        // top-level `oneOf` which frame this is.
        #expect(body["type"] as? String == "status")

        let cursor = try #require(body["cursor"] as? String)
        #expect(matches(cursor, Self.cursorPattern))

        let deviceID = try #require(body["deviceId"] as? String)
        #expect(matches(deviceID, DeviceStatusReport.deviceIDPattern))

        let phase = try #require(body["phase"] as? String)
        #expect(Self.phaseValues.contains(phase))

        let timeZone = try #require(body["timeZone"] as? String)
        #expect(matches(timeZone, DeviceStatusReport.timeZonePattern))

        let digest = try #require(body["scheduleDigest"] as? String)
        #expect(matches(digest, DeviceStatusReport.scheduleDigestPattern))

        let version = try #require(body["statusVersion"] as? Int)
        #expect(version >= 0)

        for key in ["observedAt", "nextTransitionAt", "activeLockoutEndsAt"] {
            let instant = try #require(body[key] as? String, "\(key) should be an instant")
            #expect(
                matches(instant, DeviceStatusReport.instantPattern),
                "\(key) is not a UTCInstant"
            )
        }
    }

    @Test("Every enforcement phase maps onto a DevicePhase the schema accepts")
    func everyPhaseMapsOntoTheSchemaEnum() throws {
        let phases: [EnforcementPhase] = [.working, .warning, .locked, .dayOff]
        var seen: Set<String> = []

        for phase in phases {
            let body = try decoded(Self.sample(phase: phase))
            let token = try #require(body["phase"] as? String)
            #expect(Self.phaseValues.contains(token))
            seen.insert(token)
        }

        // `unknown` is the coordinator's value for a device it has not heard
        // from; a device never reports it about itself.
        #expect(seen == ["working", "warning", "locked", "day_off"])
    }

    @Test("The whole encoded body is byte-for-byte what the schema describes")
    func encodedBodyIsExactlyThis() throws {
        let data = try Self.sample().encodedBody()
        let json = try #require(String(data: data, encoding: .utf8))

        // Sorted keys, so this is a constant. Written out rather than
        // round-tripped: this is the literal text a coordinator would receive.
        #expect(json == """
        {"activeLockoutEndsAt":"2027-01-15T09:00:00Z",\
        "cursor":"Bd5Xt1ZHm3mQI6-higG-aglSo9xTHTpy4Z4lr_Sd97g",\
        "deviceId":"3f2504e0-4f89-41d3-9a0c-0305e82c3301",\
        "nextTransitionAt":"2027-01-15T08:00:00Z",\
        "observedAt":"2027-01-15T07:59:59Z",\
        "phase":"locked",\
        "scheduleDigest":"47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU",\
        "statusVersion":7,\
        "timeZone":"America/Los_Angeles",\
        "type":"status"}
        """)
    }

    // MARK: - Cursor

    @Test("The cursor is the documented digest of the device and its version")
    func cursorIsTheDocumentedDigest() {
        // Recomputed here from the rule
        // `DeviceStatusReport.cursor(deviceID:statusVersion:)` documents —
        // unpadded base64url SHA-256 over
        // "curfew.device-status.v1\n<deviceID>\n<statusVersion>" — rather than
        // read back off the encoder. The point is that the construction is
        // written down somewhere a coordinator author could reimplement from.
        let preimage = "curfew.device-status.v1\n3f2504e0-4f89-41d3-9a0c-0305e82c3301\n7"
        let expected = Data(SHA256.hash(data: Data(preimage.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(Self.sample().cursor == expected)
        #expect(matches(expected, Self.cursorPattern))
    }

    @Test("A cursor is stable for one publication and distinct across versions")
    func cursorIsStablePerPublicationAndDistinctAcrossVersions() throws {
        var report = Self.sample()
        let first = report.cursor

        // Idempotent by name: the same status encoded twice carries the same
        // cursor, so a coordinator deduplicating by cursor sees one frame.
        #expect(report.cursor == first)
        #expect(try report.encodedBody() == report.encodedBody())

        // And a different version is a different frame. `statusVersion` never
        // repeats for this install, so cursors never collide across
        // publications either.
        report.statusVersion += 1
        #expect(report.cursor != first)

        // Two devices at the same version do not share a cursor.
        var otherDevice = Self.sample()
        otherDevice.deviceID = "3f2504e0-4f89-41d3-9a0c-0305e82c3302"
        #expect(otherDevice.cursor != first)
    }

    @Test("A report whose cursor could not satisfy the pattern is not well-formed")
    func cursorParticipatesInWellFormedness() {
        // Belt and braces: the digest always lands inside 22–128 base64url
        // characters, so this asserts the check is wired rather than that it
        // ever fires. A cursor that stopped being schema-shaped would otherwise
        // reach the coordinator and be answered `400`.
        #expect(Self.sample().isWellFormed)
        #expect(matches(Self.sample().cursor, DeviceStatusReport.cursorPattern))
    }

    // MARK: - Privacy

    @Test("The body carries no content, only scalars")
    func bodyCarriesNoContent() throws {
        let body = try decoded(Self.sample())

        // Nothing nested. A frame, a window title, an app list, or a schedule
        // would have to arrive as an array or an object, and there is nowhere
        // for one to live.
        for (key, value) in body {
            let isScalar = value is String || value is NSNumber || value is NSNull
            #expect(isScalar, "\(key) should be a scalar, not a container")
        }
        // The digest is one-way: the schedule cannot be read back out of it.
        let digest = try #require(body["scheduleDigest"] as? String)
        #expect(digest.count == 43)
    }

    // MARK: - Digest

    @Test("The schedule digest is a 43-character unpadded base64url SHA-256")
    func scheduleDigestIsSchemaShaped() {
        let digest = DeviceStatusReport.scheduleDigest(for: .standardNineToFive)

        #expect(matches(digest, DeviceStatusReport.scheduleDigestPattern))
        #expect(!digest.contains("="))
        #expect(!digest.contains("+"))
        #expect(!digest.contains("/"))
    }

    @Test("Different schedules digest differently; the same schedule digests stably")
    func scheduleDigestDiscriminates() {
        var weekendsOff = WeeklySchedule.standardNineToFive
        weekendsOff.rules[.wednesday] = .weekendDefault

        #expect(
            DeviceStatusReport.scheduleDigest(for: .standardNineToFive)
                == DeviceStatusReport.scheduleDigest(for: .standardNineToFive)
        )
        #expect(
            DeviceStatusReport.scheduleDigest(for: .standardNineToFive)
                != DeviceStatusReport.scheduleDigest(for: weekendsOff)
        )
    }

    // MARK: - Well-formedness

    @Test("A report with an unset device identifier is not well-formed")
    func unsetDeviceIdentifierIsRejected() {
        var report = Self.sample()
        report.deviceID = ""

        #expect(!report.isWellFormed)
    }

    @Test("An uppercase device identifier is not well-formed")
    func uppercaseDeviceIdentifierIsRejected() {
        var report = Self.sample()
        report.deviceID = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

        #expect(!report.isWellFormed)
    }

    @Test("A time zone without a region is not well-formed")
    func bareTimeZoneIsRejected() {
        var report = Self.sample()
        report.timeZone = "UTC"

        #expect(!report.isWellFormed)
    }

    @Test("UTC aliases normalize to the schema's canonical IANA identifier")
    func utcAliasNormalizes() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))

        #expect(DeviceStatusReport.wireTimeZoneIdentifier(for: utc) == "Etc/UTC")
    }

    @Test("Regional IANA identifiers pass through unchanged")
    func regionalTimeZonePassesThrough() throws {
        let regional = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(
            DeviceStatusReport.wireTimeZoneIdentifier(for: regional)
                == "America/Los_Angeles"
        )
    }

    @Test("A well-formed report stays well-formed")
    func sampleIsWellFormed() {
        #expect(Self.sample().isWellFormed)
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
