import CryptoKit
@testable import Curfew
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncMappingTests: XCTestCase {
    func testProofChallengeDecodesCoordinatorNonceFromReleasedContract() throws {
        let json = #"{"coordinatorNonce":"AAAAAAAAAAAAAAAAAAAAAA","# +
            #""expiresAt":"2026-09-05T08:35:00Z","keyEpoch":7}"#
        let data = Data(json.utf8)

        let challenge = try JSONDecoder().decode(NativeDeviceProofChallenge.self, from: data)

        XCTAssertEqual(challenge.coordinatorNonce, "AAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(challenge.keyEpoch, 7)
    }

    func testRemoteDeliveryMappingPreservesTheOpaqueEnvelopeAndCursor() {
        let batch = RemoteCommandDeliveryBatch(commands: [
            RemoteCommandDelivery(
                commandEnvelope: CommandCommandEnvelope(compactJws: "header.payload.signature"),
                cursor: "cursor_018f4f45cafe7f009a82e47805fb4d34",
                type: .command
            )
        ])

        let deliveries = NativeAccountSyncTransport.remoteCommandDeliveries(batch)

        XCTAssertEqual(deliveries, [
            PendingRemoteCommandDelivery(
                cursor: "cursor_018f4f45cafe7f009a82e47805fb4d34",
                envelope: SignedRemoteLockoutCommandEnvelope(
                    compactJWS: "header.payload.signature"
                )
            )
        ])
    }

    func testDaemonResultMapsExactlyToReleasedProtocol() throws {
        let commandID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")
        )
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let resolvedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = resolvedAt.addingTimeInterval(900)
        let local = Curfew.RemoteCommandResult(
            commandID: commandID,
            deviceID: deviceID,
            sequence: 7,
            stage: .applied,
            resolvedAt: resolvedAt,
            appliedDeadline: deadline
        )

        let wire = try NativeAccountSyncTransport.remoteCommandResult(local)

        XCTAssertEqual(wire.commandID, commandID.uuidString.lowercased())
        XCTAssertEqual(wire.deviceID, deviceID.uuidString.lowercased())
        XCTAssertEqual(wire.sequence, 7)
        XCTAssertEqual(wire.stage, CurfewProtocols.RemoteCommandResultStage.applied)
        XCTAssertEqual(wire.resolvedAt, "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(wire.appliedDeadline, "2027-01-15T08:15:00.000Z")
        XCTAssertNil(wire.rejectionCode)
    }

    func testEnrollmentReceiptCreatesCanonicalDaemonVerifierIdentity() throws {
        let receipt = NativeDeviceEnrollmentReceipt(
            deviceID: "018f4f45-cafe-7f00-9a82-e47805fb4d35",
            enrolledAt: "2026-09-05T08:35:00Z",
            protocolVersion: "0.0",
            userID: "account_018f4f45cafe7f009a82e47805fb4d34"
        )

        let enrollment = try NativeAccountSyncTransport.remoteCommandEnrollment(receipt)

        XCTAssertEqual(enrollment.userID, "account_018f4f45cafe7f009a82e47805fb4d34")
        XCTAssertEqual(
            enrollment.deviceID,
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
    }

    func testEnrollmentFinalizerPersistsAuthenticatedDaemonIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("remote-enrollment.json")
        )
        let finalizer = RemoteCommandEnrollmentFinalizer(store: store)
        let data = try NativeDeviceEnrollmentReceipt(
            deviceID: "018f4f45-cafe-7f00-9a82-e47805fb4d35",
            enrolledAt: "2026-09-05T08:35:00Z",
            protocolVersion: "0.0",
            userID: "account_018f4f45cafe7f009a82e47805fb4d34"
        ).jsonData()

        try finalizer.install(receiptData: data)

        XCTAssertEqual(
            try store.load()?.userID,
            "account_018f4f45cafe7f009a82e47805fb4d34"
        )
    }

    func testDeviceProofBindsTokenMethodURLNonceAndBody() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identifier = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")
        )
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
        let deviceID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AccountDeviceKeyStore(secretStore: NativeMappingMemorySecretStore())
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
            keyEpoch: 7,
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
        XCTAssertEqual(request.keyEpoch, 7)
        XCTAssertFalse(request.remoteControlEnabled)
        XCTAssertEqual(request.state, "oauth-state")
        XCTAssertNotNil(object["deviceProof"])
        XCTAssertNil(object["displayName"])
        XCTAssertNil(object["platform"])
    }

    func testPeerRootDistributionSkipsTheCurrentDevice() throws {
        let currentID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")
        )
        let peerID = try XCTUnwrap(
            UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")
        )
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
            protocolVersion: "0.0",
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

private final class NativeMappingMemorySecretStore: AccountSecretStoring {
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
