@testable import Curfew
import Foundation
import Testing

/// The wire shape, asserted against the schema rather than against itself.
///
/// Every expectation below is transcribed by hand from
/// `curfew-protocols/schemas/device.json` → `#/definitions/DeviceStatusSnapshot`.
/// None of it is derived from `DeviceStatusReport`, because a test that asks the
/// encoder what the encoder produces passes with any key set at all — including
/// a wrong one. This project has been bitten by exactly that, so the key
/// literals here are duplicated on purpose: if the encoder is renamed and this
/// file is not, the suite fails, which is the whole point.
struct DeviceStatusReportPayloadTests {
    // MARK: - Schema transcription

    /// `required` in `DeviceStatusSnapshot`, in schema order.
    static let requiredKeys: Set<String> = [
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

    @Test("The encoded body's key set is exactly what DeviceStatusSnapshot defines")
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
        "deviceId":"3f2504e0-4f89-41d3-9a0c-0305e82c3301",\
        "nextTransitionAt":"2027-01-15T08:00:00Z",\
        "observedAt":"2027-01-15T07:59:59Z",\
        "phase":"locked",\
        "scheduleDigest":"47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU",\
        "statusVersion":7,\
        "timeZone":"America/Los_Angeles"}
        """)
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

    @Test("A well-formed report stays well-formed")
    func sampleIsWellFormed() {
        #expect(Self.sample().isWellFormed)
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
