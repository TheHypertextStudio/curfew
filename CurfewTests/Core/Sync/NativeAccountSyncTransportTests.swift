import CryptoKit
@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncTransportTests: XCTestCase {
    func testDeviceProofBindsTokenMethodURLNonceAndBody() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identifier = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34"))
        let body = Data(#"{"deviceId":"018f4f45-cafe-7f00-9a82-e47805fb4d35"}"#.utf8)
        let proof = try AccountDeviceProofFactory(
            now: { now },
            identifier: { identifier }
        ).make(.init(
            accessToken: "resource-bound-access-token",
            nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            method: "POST",
            url: XCTUnwrap(
                URL(string: "https://curfew-sync.hypertext.studio/sync/devices/enroll")
            ),
            body: body,
            signingPrivateKey: key.rawRepresentation
        ))

        let parts = proof.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        let header = try XCTUnwrap(decode(String(parts[0])))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: header) as? [String: String],
            ["alg": "ES256", "typ": "curfew-device-proof+jws"]
        )
        let claims = try DeviceProofClaims(data: XCTUnwrap(decode(String(parts[1]))))
        XCTAssertEqual(claims.httpMethod, "POST")
        XCTAssertEqual(
            claims.canonicalURL,
            "https://curfew-sync.hypertext.studio/sync/devices/enroll"
        )
        XCTAssertEqual(claims.jti, identifier.uuidString.lowercased())
        XCTAssertEqual(claims.nonce, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertNotNil(claims.accessTokenHash)
        XCTAssertNotNil(claims.bodyDigest)

        let signature = try P256.Signing.ECDSASignature(
            rawRepresentation: XCTUnwrap(decode(String(parts[2])))
        )
        XCTAssertTrue(key.publicKey.isValidSignature(
            signature,
            for: Data("\(parts[0]).\(parts[1])".utf8)
        ))
    }

    func testEnrollmentRequestUsesGeneratedPrivacyMinimalContract() throws {
        let deviceID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35"))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AccountDeviceKeyStore(secretStore: NativeTransportMemorySecretStore())
        let bootstrap = try store.createEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            createdAt: createdAt
        )
        let keys = try XCTUnwrap(store.load(deviceID: deviceID))
        let request = try AccountDeviceEnrollmentRequestBuilder(
            proofFactory: AccountDeviceProofFactory(
                now: { createdAt },
                identifier: { UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")! }
            )
        ).make(AccountDeviceEnrollmentRequestInput(
            accessToken: "resource-bound-access-token",
            nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            deviceID: deviceID,
            bootstrap: bootstrap,
            keys: keys,
            enrolledAt: createdAt,
            pkceChallenge: "pkce-challenge",
            state: "oauth-state"
        ))
        let encoded = try request.jsonData()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(request.deviceID, deviceID.uuidString.lowercased())
        XCTAssertEqual(request.keyEpoch, 1)
        XCTAssertEqual(request.state, "oauth-state")
        XCTAssertNotNil(object["deviceProof"])
        XCTAssertNil(object["displayName"])
        XCTAssertNil(object["platform"])
    }

    func testPeerRootDistributionSkipsTheCurrentDevice() throws {
        let currentID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35"))
        let peerID = try XCTUnwrap(UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36"))
        let current = enrollment(id: currentID, key: P256.KeyAgreement.PrivateKey().publicKey)
        let peer = enrollment(id: peerID, key: P256.KeyAgreement.PrivateKey().publicKey)

        let envelopes = try AccountPeerRootKeyDistributor.envelopes(
            rootKey: Data(repeating: 0x42, count: 32),
            currentDeviceID: currentID,
            devices: [current, peer],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(envelopes.map(\.recipientDeviceID), [peerID.uuidString.lowercased()])
    }

    private func enrollment(
        id: UUID,
        key: P256.KeyAgreement.PublicKey
    ) -> CurfewProtocols.AccountDeviceEnrollment {
        let local = AccountPublicKeyJWK(agreementPublicKey: key)
        let generated = CurfewProtocols.AccountPublicKeyJWK(
            crv: .p256,
            kty: .ec,
            x: local.x,
            y: local.y
        )
        return CurfewProtocols.AccountDeviceEnrollment(
            deviceID: id.uuidString.lowercased(),
            encryptionPublicKeyJwk: generated,
            enrolledAt: "2026-08-10T14:00:00Z",
            keyEpoch: 1,
            signingPublicKeyJwk: generated
        )
    }

    private func decode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

private final class NativeTransportMemorySecretStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values.removeValue(forKey: account)
    }
}
