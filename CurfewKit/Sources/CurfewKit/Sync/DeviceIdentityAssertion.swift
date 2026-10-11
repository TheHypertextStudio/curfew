import CryptoKit
import Foundation

/// The credential a Curfew device presents on the device-agent status routes.
///
/// **Shape authority.** The claims below are
/// `curfew-protocols/schemas/sync.json` →
/// `#/definitions/InternalDeviceIdentityClaims`, verbatim: six keys, no more
/// (`additionalProperties: false`) and no fewer (all six are `required`). The
/// serialised form is `#/definitions/InternalDeviceIdentityAssertion`'s
/// `compactJws`, a `CompactJWS` —
/// `^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{86}$`.
///
/// **Why HS512 and not something asymmetric.** Because that is what the
/// coordinator verifies. `curfew-sync/src/auth/device-assertion.ts` imports the
/// secret as `{name: "HMAC", hash: "SHA-512"}`, rejects any header whose `alg`
/// is not exactly `"HS512"`, and checks the MAC over
/// `base64url(header).base64url(payload)`. The 86-character signature segment
/// the schema's `CompactJWS` pattern demands is the unpadded base64url of a
/// 64-byte MAC, which is what SHA-512 produces and what SHA-256 does not — the
/// algorithm is pinned by the wire format, not chosen here.
///
/// **What this proves, stated plainly.** A symmetric MAC over a secret the
/// coordinator and every enrolled device hold proves the assertion was minted
/// by *something holding that secret*. It does not prove possession of this
/// device's own key. curfew-sync's own comment says the same thing and names
/// the successor: ES256 over the enrolled `DevicePublicKeyJWK`, verified
/// against the key stored at enrollment. When that lands, this type keeps its
/// claims and its compact serialisation and changes only how the signature is
/// computed. Until then, the secret is a shared credential and is stored like
/// one — see `DeviceAssertionSecretStore`, which puts it in the Keychain and
/// nowhere else.
public struct DeviceIdentityAssertion: Equatable {
    /// Schema `audience`: `"const": "curfew-user-coordinator"`. A constant, not
    /// a setting — a configurable audience would only ever be configured wrong,
    /// and the coordinator's parser accepts exactly this one string.
    public static let audience = "curfew-user-coordinator"

    /// The JOSE header's `alg`, which the verifier compares with `!==`.
    public static let algorithm = "HS512"

    /// How long a minted assertion is good for.
    ///
    /// Two minutes, matching ``DeviceStatusReportingPolicy/heartbeatCeilingSeconds`` —
    /// the coordinator's own freshness threshold, and the longest gap Curfew
    /// will ever leave between two publishes. So an assertion outlives the
    /// request it was minted for (the transport gives up after 10 s) and dies
    /// before the next report that would carry a fresh one. The verifier adds
    /// its own 60 s of clock-skew tolerance on each end, so the real acceptance
    /// window is 180 s — still short enough that a captured `Authorization`
    /// header is worth little, and long enough that a Mac whose clock is a
    /// minute out still authenticates.
    public static let validitySeconds: TimeInterval = 120

    /// The exact key set `InternalDeviceIdentityClaims` defines. Public for the
    /// same reason ``DeviceStatusReport/schemaKeys`` is: it is the contract, and
    /// a test that asks the encoder what the encoder emits proves nothing.
    public static let claimKeys: Set<String> = [
        "userId",
        "deviceId",
        "keyThumbprint",
        "audience",
        "issuedAt",
        "expiresAt"
    ]

    /// Schema `keyThumbprint`: 43 unpadded base64url characters — one SHA-256.
    public static let keyThumbprintPattern = "^[A-Za-z0-9_-]{43}$"

    /// Schema `CompactJWS`, verbatim. The `{86}` on the last segment is what
    /// forces a 64-byte MAC.
    public static let compactJWSPattern =
        "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]{86}$"

    /// Schema `userId`: `minLength: 1`, `maxLength: 128`.
    public static let userIDMaxLength = 128

    /// Domain-separation prefix for the thumbprint preimage, so this digest can
    /// never collide with ``DeviceStatusReport/cursor(deviceID:statusVersion:)``
    /// or ``DeviceStatusReport/scheduleDigest(for:)``, which hash different
    /// strings for different purposes with the same algorithm.
    private static let thumbprintDomain = "curfew.device-key-thumbprint.v1"

    /// The coordinator account this device belongs to. `claims.userId` is what
    /// `POST /sync/status` writes onto the `device` and `device_status` rows and
    /// what `GET /sync/status` filters a reader's devices by, so it is the
    /// user's own account identifier, entered in Settings.
    public var userID: String

    /// This device's identifier — the same value the publication carries. The
    /// route compares them and answers `403 device_mismatch` when they differ,
    /// so a device publishes its own status and nobody else's.
    public var deviceID: String

    /// When this assertion was minted. Injected rather than read from the clock
    /// so a fixed-vector test can pin the whole serialisation.
    public var issuedAt: Date

    /// Memberwise initialiser.
    public init(userID: String, deviceID: String, issuedAt: Date) {
        self.userID = userID
        self.deviceID = deviceID
        self.issuedAt = issuedAt
    }

    /// ``issuedAt`` plus ``validitySeconds``.
    public var expiresAt: Date {
        issuedAt.addingTimeInterval(Self.validitySeconds)
    }

    /// Schema `keyThumbprint` for this device — see
    /// ``keyThumbprint(deviceID:)``.
    public var keyThumbprint: String {
        Self.keyThumbprint(deviceID: deviceID)
    }

    /// Whether every claim satisfies the schema's constraints. Checked before
    /// anything is signed, so a device with an unset account or identifier
    /// stays quiet rather than retrying a guaranteed 401 every heartbeat.
    public var isWellFormed: Bool {
        !userID.isEmpty
            && userID.count <= Self.userIDMaxLength
            && deviceID.range(
                of: DeviceStatusReport.deviceIDPattern,
                options: .regularExpression
            ) != nil
    }

    /// The schema `keyThumbprint` for a device: unpadded base64url SHA-256 over
    /// `"curfew.device-key-thumbprint.v1\n<deviceID>"`.
    ///
    /// **Why a device may mint this at all.** Nothing validates it today.
    /// `verifyDeviceIdentityAssertion` checks the header's `alg`, the MAC, and
    /// the two instants, and never looks at `keyThumbprint`; the route stores it
    /// verbatim on the `device` row (`keyThumbprint: claims.keyThumbprint`,
    /// `onConflictDoUpdate`) without comparing it against any registered key,
    /// because there is no enrollment yet to have registered one. So the only
    /// live constraint is the schema's `^[A-Za-z0-9_-]{43}$`.
    ///
    /// **Why derived rather than random.** The field's eventual meaning is "the
    /// thumbprint of this device's key", and its eventual behaviour is to be
    /// stable for as long as that key is. A fresh random value per request would
    /// satisfy the pattern while rewriting the stored row on every heartbeat,
    /// which is the opposite of the property the column exists to hold — and it
    /// would make the day enrollment starts checking it a silent, intermittent
    /// 401 rather than a clean one. A digest of the device identifier is stable
    /// per device, distinct across devices, and reveals nothing the assertion
    /// does not already carry in `deviceId` beside it.
    ///
    /// **What it is not.** It is not a key thumbprint. There is no per-device
    /// key yet to take one of. When enrollment lands and a device holds a real
    /// `DevicePublicKeyJWK`, this becomes the RFC 7638 thumbprint of that key
    /// and the stored value changes once, at enrollment, where a rotation
    /// belongs.
    public static func keyThumbprint(deviceID: String) -> String {
        let preimage = "\(thumbprintDomain)\n\(deviceID)"
        return Base64URL.encode(Data(SHA256.hash(data: Data(preimage.utf8))))
    }

    /// The claims object, with keys and value formats exactly as
    /// `InternalDeviceIdentityClaims` defines them.
    ///
    /// `sortedKeys` keeps the bytes deterministic, which is what lets the whole
    /// compact serialisation be pinned by a fixed vector: HMAC is a function of
    /// the bytes, so a payload whose key order wandered would change the
    /// signature too.
    ///
    /// - Throws: Only if `JSONSerialization` rejects the object, which it cannot
    ///   for a dictionary of strings.
    public func encodedClaims() throws -> Data {
        let claims: [String: Any] = [
            "userId": userID,
            "deviceId": deviceID,
            "keyThumbprint": keyThumbprint,
            "audience": Self.audience,
            "issuedAt": DeviceStatusReport.instant(issuedAt),
            "expiresAt": DeviceStatusReport.instant(expiresAt)
        ]
        return try JSONSerialization.data(
            withJSONObject: claims,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// The compact JWS to send as `Authorization: Bearer <value>`, or `nil` when
    /// this device cannot sign one.
    ///
    /// `nil` — meaning *publish nothing* — whenever the secret is unset or the
    /// claims would not satisfy the schema. That is the same contract
    /// ``DeviceStatusReportingPolicy/resolvedEndpoint`` has for an unconfigured
    /// address, and it is deliberately the same shape: a Curfew that has not
    /// been given a credential talks to nobody, exactly like a Curfew that has
    /// not been given an address.
    public func compactJWS(signedWith secret: String) -> String? {
        guard !secret.isEmpty, isWellFormed else { return nil }
        guard let headerData = try? JSONSerialization.data(
            withJSONObject: ["alg": Self.algorithm],
            options: [.sortedKeys]
        ), let claimsData = try? encodedClaims() else { return nil }

        let signingInput = "\(Base64URL.encode(headerData)).\(Base64URL.encode(claimsData))"
        let mac = HMAC<SHA512>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(secret.utf8))
        )
        return "\(signingInput).\(Base64URL.encode(Data(mac)))"
    }
}
