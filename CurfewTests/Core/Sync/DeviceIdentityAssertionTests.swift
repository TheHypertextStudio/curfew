import CryptoKit
@testable import Curfew
import Foundation
import Testing

/// The credential, asserted against the schema and against an independent
/// recomputation rather than against itself.
///
/// Every literal below is transcribed by hand from
/// `curfew-protocols/schemas/sync.json` →
/// `#/definitions/InternalDeviceIdentityClaims` and `#/definitions/CompactJWS`,
/// and the fixed vector at the end was computed with a separate HMAC-SHA-512
/// implementation, not with the code under test. A suite that asks the signer
/// what the signer produces passes for every possible serialisation, including
/// one the coordinator would answer 401 to.
struct DeviceIdentityAssertionTests {
    // MARK: - Schema transcription

    /// `required` in `InternalDeviceIdentityClaims`. `additionalProperties` is
    /// `false`, so this is also the complete allowed set.
    static let claimKeys: Set<String> = [
        "userId",
        "deviceId",
        "keyThumbprint",
        "audience",
        "issuedAt",
        "expiresAt"
    ]

    /// `#/definitions/CompactJWS`, verbatim.
    static let compactJWSPattern = "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]{86}$"

    /// `keyThumbprint`'s pattern, verbatim.
    static let keyThumbprintPattern = "^[A-Za-z0-9_-]{43}$"

    /// `#/definitions/UTCInstant`, verbatim.
    static let instantPattern =
        "^[0-9]{4}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])T"
            + "([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]{1,9})?Z$"

    // MARK: - Fixtures

    static let secret = "curfew-test-shared-secret"
    static let userID = "user_01HZTESTACCOUNT"
    static let deviceID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

    /// A fully populated assertion at a fixed instant, so everything derived
    /// from it — including the MAC — is a constant.
    static func sample(
        userID: String = DeviceIdentityAssertionTests.userID,
        deviceID: String = DeviceIdentityAssertionTests.deviceID,
        issuedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> DeviceIdentityAssertion {
        DeviceIdentityAssertion(userID: userID, deviceID: deviceID, issuedAt: issuedAt)
    }

    // MARK: - Claim set

    @Test("The claims are exactly the six InternalDeviceIdentityClaims defines")
    func claimSetMatchesTheSchemaExactly() throws {
        let object = try JSONSerialization.jsonObject(with: Self.sample().encodedClaims())
        let claims = try #require(object as? [String: Any])

        #expect(Set(claims.keys) == Self.claimKeys)
        // Stated as two halves so a failure says which one broke. A missing
        // required claim and an extra undeclared one are different bugs, and
        // `additionalProperties: false` means the second is rejected outright.
        #expect(Self.claimKeys.isSubset(of: Set(claims.keys)))
        #expect(Set(claims.keys).subtracting(Self.claimKeys).isEmpty)
    }

    @Test("Every claim matches the schema's type and pattern")
    func claimValuesMatchTheSchema() throws {
        let object = try JSONSerialization.jsonObject(with: Self.sample().encodedClaims())
        let claims = try #require(object as? [String: Any])

        #expect(claims["userId"] as? String == Self.userID)
        #expect(claims["deviceId"] as? String == Self.deviceID)
        // `const: "curfew-user-coordinator"` — one value, not a setting.
        #expect(claims["audience"] as? String == "curfew-user-coordinator")

        let thumbprint = try #require(claims["keyThumbprint"] as? String)
        #expect(matches(thumbprint, Self.keyThumbprintPattern))

        for key in ["issuedAt", "expiresAt"] {
            let instant = try #require(claims[key] as? String, "\(key) should be an instant")
            #expect(matches(instant, Self.instantPattern), "\(key) is not a UTCInstant")
        }
    }

    @Test("The device identifier in the claims is the one the publication carries")
    func deviceIdentifierMatchesThePublication() throws {
        // `POST /sync/status` answers `403 device_mismatch` when
        // `publication.deviceId !== claims.deviceId`, so these two are one
        // value or every report fails.
        let object = try JSONSerialization.jsonObject(with: Self.sample().encodedClaims())
        let claims = try #require(object as? [String: Any])
        let report = DeviceStatusReportPayloadTests.sample()

        #expect(claims["deviceId"] as? String == report.deviceID)
    }

    // MARK: - Validity window

    @Test("The validity window is two minutes, opening at the moment of minting")
    func validityWindowIsTwoMinutes() {
        let assertion = Self.sample()

        #expect(DeviceIdentityAssertion.validitySeconds == 120)
        #expect(assertion.expiresAt.timeIntervalSince(assertion.issuedAt) == 120)
        // The coordinator's freshness threshold, and so the longest gap Curfew
        // will ever leave between two publishes: an assertion cannot outlive
        // the report that would carry its replacement.
        #expect(
            DeviceIdentityAssertion.validitySeconds
                == TimeInterval(DeviceStatusReportingPolicy.heartbeatCeilingSeconds)
        )
    }

    @Test("The window comfortably outlives the request it is minted for")
    func windowOutlivesTheRequestTimeout() {
        // The transport abandons a publish after 10 s. An assertion that could
        // expire mid-request would produce intermittent 401s that look like a
        // network problem.
        #expect(
            DeviceIdentityAssertion.validitySeconds
                > URLSessionDeviceStatusTransport.timeoutSeconds
        )
    }

    // MARK: - Key thumbprint

    @Test("The thumbprint is the documented digest of the device identifier")
    func thumbprintIsTheDocumentedDigest() {
        // Recomputed from the rule the doc comment states — unpadded base64url
        // SHA-256 over "curfew.device-key-thumbprint.v1\n<deviceID>" — rather
        // than read back off the implementation, so the construction is written
        // down somewhere a coordinator author could reimplement from.
        let preimage = "curfew.device-key-thumbprint.v1\n\(Self.deviceID)"
        let expected = Data(SHA256.hash(data: Data(preimage.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(DeviceIdentityAssertion.keyThumbprint(deviceID: Self.deviceID) == expected)
        #expect(matches(expected, Self.keyThumbprintPattern))
    }

    @Test("A thumbprint is stable per device and distinct across devices")
    func thumbprintIsStableAndDistinct() {
        let first = DeviceIdentityAssertion.keyThumbprint(deviceID: Self.deviceID)

        // Stable: the column exists to hold a value that changes when a key
        // changes, and re-minting an assertion is not a key change.
        #expect(DeviceIdentityAssertion.keyThumbprint(deviceID: Self.deviceID) == first)
        #expect(Self.sample().keyThumbprint == first)
        #expect(Self.sample(issuedAt: Date(timeIntervalSince1970: 42)).keyThumbprint == first)

        // Distinct: two devices on one account do not collide.
        let other = DeviceIdentityAssertion
            .keyThumbprint(deviceID: "3f2504e0-4f89-41d3-9a0c-0305e82c3302")
        #expect(other != first)
        #expect(matches(other, Self.keyThumbprintPattern))
    }

    @Test("The thumbprint cannot collide with the cursor over the same device")
    func thumbprintIsDomainSeparatedFromTheCursor() {
        // Both are base64url SHA-256 over a string containing the device id.
        // The domain prefixes are what keep them from ever being the same
        // digest for the same input.
        #expect(
            DeviceIdentityAssertion.keyThumbprint(deviceID: Self.deviceID)
                != DeviceStatusReport.cursor(deviceID: Self.deviceID, statusVersion: 0)
        )
    }

    // MARK: - Signing

    @Test("A minted assertion is a schema-shaped CompactJWS")
    func mintedAssertionIsSchemaShaped() throws {
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))

        #expect(matches(jws, Self.compactJWSPattern))
        let segments = jws.split(separator: ".", omittingEmptySubsequences: false)
        #expect(segments.count == 3)
        // 86 unpadded base64url characters is 64 bytes, which is what SHA-512
        // produces and SHA-256 does not — the schema pins the algorithm.
        #expect(segments[2].count == 86)
    }

    @Test("The header is the one the verifier compares against")
    func headerDeclaresHS512() throws {
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))
        let segments = jws.split(separator: ".").map(String.init)
        let header = try #require(decodeJSON(segments[0]))

        // `verifyDeviceIdentityAssertion` rejects anything where
        // `header.alg !== "HS512"`, before it even looks at the MAC.
        #expect(header["alg"] as? String == "HS512")
        #expect(Set(header.keys) == ["alg"])
    }

    @Test("The signature is a real HMAC-SHA-512 over header.payload, recomputed here")
    func signatureVerifiesIndependently() throws {
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))
        let segments = jws.split(separator: ".").map(String.init)
        let signedInput = "\(segments[0]).\(segments[1])"

        // The verification the coordinator does, done here: import the same
        // secret as an HMAC-SHA-512 key and check the MAC over
        // `base64url(header).base64url(payload)`.
        let key = SymmetricKey(data: Data(Self.secret.utf8))
        let signature = try #require(decodeBase64URL(segments[2]))
        #expect(HMAC<SHA512>.isValidAuthenticationCode(
            signature,
            authenticating: Data(signedInput.utf8),
            using: key
        ))

        // And the payload really is the claims, so the MAC covers what it
        // looks like it covers.
        let claims = try #require(decodeJSON(segments[1]))
        #expect(Set(claims.keys) == Self.claimKeys)
        #expect(claims["userId"] as? String == Self.userID)
    }

    @Test("A signature made with a different secret does not verify")
    func signatureIsSecretDependent() throws {
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))
        let segments = jws.split(separator: ".").map(String.init)
        let signature = try #require(decodeBase64URL(segments[2]))

        // The negative half of the test above: without it, a signer that
        // ignored the secret entirely would still pass.
        #expect(!HMAC<SHA512>.isValidAuthenticationCode(
            signature,
            authenticating: Data("\(segments[0]).\(segments[1])".utf8),
            using: SymmetricKey(data: Data("some-other-secret".utf8))
        ))
        #expect(Self.sample().compactJWS(signedWith: "some-other-secret") != jws)
    }

    @Test("Changing any claim changes the assertion")
    func everyClaimIsCovered() throws {
        let baseline = try #require(Self.sample().compactJWS(signedWith: Self.secret))

        #expect(Self.sample(userID: "user_other").compactJWS(signedWith: Self.secret) != baseline)
        #expect(
            Self.sample(deviceID: "3f2504e0-4f89-41d3-9a0c-0305e82c3302")
                .compactJWS(signedWith: Self.secret) != baseline
        )
        #expect(
            Self.sample(issuedAt: Date(timeIntervalSince1970: 1_800_000_001))
                .compactJWS(signedWith: Self.secret) != baseline
        )
    }

    // MARK: - The fixed vector

    @Test("The whole compact JWS is byte-for-byte this")
    func mintedAssertionIsExactlyThis() throws {
        // HMAC is deterministic, so with a fixed secret and fixed claims the
        // entire credential is a constant. This value was computed with a
        // separate HMAC-SHA-512 implementation over the header
        // `{"alg":"HS512"}` and the sorted-key claims object, so it pins the
        // header bytes, the claim spelling, the key order, the instant format,
        // the thumbprint derivation, the base64url alphabet, and the absence of
        // padding all at once. Any change to any of them fails here, which is
        // the point: every one of those is a silent 401 in production.
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))

        #expect(jws == """
        eyJhbGciOiJIUzUxMiJ9.\
        eyJhdWRpZW5jZSI6ImN1cmZldy11c2VyLWNvb3JkaW5hdG9yIiwiZGV2aWNlSWQiOiIzZjI1MDRlMC00\
        Zjg5LTQxZDMtOWEwYy0wMzA1ZTgyYzMzMDEiLCJleHBpcmVzQXQiOiIyMDI3LTAxLTE1VDA4OjAyOjAw\
        WiIsImlzc3VlZEF0IjoiMjAyNy0wMS0xNVQwODowMDowMFoiLCJrZXlUaHVtYnByaW50IjoiSi1YeXNU\
        bXBfVDFaaXBGNWI2ZlN1SzZXNlNxcjd0U1JBWVF3ODJLTUN5cyIsInVzZXJJZCI6InVzZXJfMDFIWlRF\
        U1RBQ0NPVU5UIn0.\
        XqKfVl3gO9nI7nQb4RDoM9YomoRr1_VrxYJriStI7qUsZIYWtX2P5Q7buiZuNeYcO8EjK8skmUPyw53c\
        nXv8bw
        """)
    }

    @Test("The vector's payload decodes to the exact claims JSON")
    func vectorPayloadIsExactlyThis() throws {
        let jws = try #require(Self.sample().compactJWS(signedWith: Self.secret))
        let segments = jws.split(separator: ".").map(String.init)
        let payload = try #require(decodeBase64URL(segments[1]))

        // The same constant read the other way round, so a failure in the test
        // above says whether the claims moved or only the signature did.
        #expect(String(data: payload, encoding: .utf8) == """
        {"audience":"curfew-user-coordinator",\
        "deviceId":"3f2504e0-4f89-41d3-9a0c-0305e82c3301",\
        "expiresAt":"2027-01-15T08:02:00Z",\
        "issuedAt":"2027-01-15T08:00:00Z",\
        "keyThumbprint":"J-XysTmp_T1ZipF5b6fSuK6W6Sqr7tSRAYQw82KMCys",\
        "userId":"user_01HZTESTACCOUNT"}
        """)
    }

    // MARK: - Refusing to sign

    @Test("Nothing is signed without a secret")
    func unsetSecretSignsNothing() {
        #expect(Self.sample().compactJWS(signedWith: "") == nil)
    }

    @Test("Nothing is signed for an account or a device the schema would reject")
    func malformedClaimsSignNothing() {
        // `userId` is `minLength: 1`.
        #expect(Self.sample(userID: "").compactJWS(signedWith: Self.secret) == nil)
        // `maxLength: 128`.
        let tooLong = String(repeating: "u", count: 129)
        #expect(Self.sample(userID: tooLong).compactJWS(signedWith: Self.secret) == nil)
        #expect(Self.sample(userID: String(repeating: "u", count: 128)).isWellFormed)

        // `deviceId` is a `CanonicalUUID`: lowercase, and never empty.
        #expect(Self.sample(deviceID: "").compactJWS(signedWith: Self.secret) == nil)
        #expect(Self.sample(deviceID: "not-a-uuid").compactJWS(signedWith: Self.secret) == nil)
        #expect(
            Self.sample(deviceID: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")
                .compactJWS(signedWith: Self.secret) == nil
        )
    }

    // MARK: - Helpers

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Decodes an unpadded base64url segment, re-adding the padding
    /// `Foundation`'s decoder insists on.
    private func decodeBase64URL(_ segment: String) -> Data? {
        var padded = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        return Data(base64Encoded: padded)
    }

    private func decodeJSON(_ segment: String) -> [String: Any]? {
        guard let data = decodeBase64URL(segment) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
