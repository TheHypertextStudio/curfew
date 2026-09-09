import CurfewProtocols
import Foundation

struct AccountDeviceEnrollmentRequestInput {
    let accessToken: String
    let nonce: String
    let keyEpoch: Int
    let deviceID: UUID
    let bootstrap: AccountEnrollmentBootstrap
    let keys: AccountDeviceKeyMaterial
    let enrolledAt: Date
    let pkceChallenge: String
    let state: String
    let syncResource: URL
}

struct AccountDeviceEnrollmentRequestBuilder {
    let proofFactory: AccountDeviceProofFactory

    init(proofFactory: AccountDeviceProofFactory = AccountDeviceProofFactory()) {
        self.proofFactory = proofFactory
    }

    func make(_ input: AccountDeviceEnrollmentRequestInput) throws -> DeviceEnrollmentRequest {
        let identifier = input.deviceID.uuidString.lowercased()
        let enrolledAtValue = Self.dateFormatter.string(from: input.enrolledAt)
        let unsigned = DeviceEnrollmentRequest(
            coordinatorNonce: input.nonce,
            deviceID: identifier,
            deviceProof: DeviceProof(compactJws: ""),
            encryptionPublicKeyJwk: Self.generatedJWK(input.bootstrap.encryptionPublicKey),
            enrolledAt: enrolledAtValue,
            keyEpoch: input.keyEpoch,
            pkceChallenge: input.pkceChallenge,
            protocolVersion: "0.0",
            remoteControlEnabled: false,
            signingPublicKeyJwk: Self.generatedJWK(input.bootstrap.signingPublicKey),
            state: input.state
        )
        guard var body = try JSONSerialization.jsonObject(
            with: unsigned.jsonData()
        ) as? [String: Any] else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        body.removeValue(forKey: "deviceProof")
        let unsignedBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let endpoint = input.syncResource.appending(path: "/sync/devices/enroll")
        let proof = try proofFactory.make(.init(
            accessToken: input.accessToken,
            nonce: input.nonce,
            method: "POST",
            url: endpoint,
            body: unsignedBody,
            signingPrivateKey: input.keys.signingPrivateKey
        ))
        return DeviceEnrollmentRequest(
            coordinatorNonce: input.nonce,
            deviceID: identifier,
            deviceProof: DeviceProof(compactJws: proof),
            encryptionPublicKeyJwk: Self.generatedJWK(input.bootstrap.encryptionPublicKey),
            enrolledAt: enrolledAtValue,
            keyEpoch: input.keyEpoch,
            pkceChallenge: input.pkceChallenge,
            protocolVersion: "0.0",
            remoteControlEnabled: false,
            signingPublicKeyJwk: Self.generatedJWK(input.bootstrap.signingPublicKey),
            state: input.state
        )
    }

    private static func generatedJWK(_ value: AccountPublicKeyJWK) -> DevicePublicKeyJWK {
        DevicePublicKeyJWK(crv: .p256, kty: .ec, x: value.x, y: value.y)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct RemoteCommandEnrollmentFinalizer {
    let store: RemoteCommandEnrollmentStore

    func install(receiptData: Data) throws {
        let receipt = try NativeDeviceEnrollmentReceipt(data: receiptData)
        try store.save(NativeAccountSyncTransport.remoteCommandEnrollment(receipt))
    }
}

struct PreparedDeviceRegistration {
    let request: DeviceEnrollmentRequest
    let localEnrollment: AccountDeviceEnrollment
    let bootstrap: AccountEnrollmentBootstrap
    let recoveryEnvelope: RecoveryKeyEnvelope
}
