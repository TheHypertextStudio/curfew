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
        let endpoint = URL(
            string: "https://curfew-sync.hypertext.studio/sync/devices/enroll"
        )!
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

enum NativeAccountEnrollmentState: Equatable {
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
}

@MainActor
final class NativeAccountDeviceEnrollmentService {
    private let secretStore: any AccountSecretStoring
    private let keyStore: AccountDeviceKeyStore
    private let session: URLSession
    private let proofFactory: AccountDeviceProofFactory
    private let remoteCommandFinalizer: RemoteCommandEnrollmentFinalizer
    private let baseURL = URL(string: "https://curfew-sync.hypertext.studio")!

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory = AccountDeviceProofFactory(),
        remoteCommandEnrollmentStore: RemoteCommandEnrollmentStore = .init(
            recordURL: SharedPaths.remoteCommandEnrollment
        )
    ) {
        self.secretStore = secretStore
        self.keyStore = AccountDeviceKeyStore(secretStore: secretStore)
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
        self.proofFactory = proofFactory
        self.remoteCommandFinalizer = RemoteCommandEnrollmentFinalizer(
            store: remoteCommandEnrollmentStore
        )
    }

    func enroll(
        grant: AccountOAuthGrant,
        deviceID: UUID,
        enrolledAt: Date = Date()
    ) async throws -> NativeAccountEnrollmentState {
        let accessToken = grant.tokens.accessToken
        let challenge = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let bootstrap = try keyStore.createEnrollment(
            deviceID: deviceID,
            keyEpoch: challenge.keyEpoch,
            createdAt: enrolledAt
        )
        guard let keys = try keyStore.load(deviceID: deviceID) else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        let enrollment = try AccountDeviceEnrollmentRequestBuilder(
            proofFactory: proofFactory
        ).make(AccountDeviceEnrollmentRequestInput(
            accessToken: accessToken,
            nonce: challenge.coordinatorNonce,
            keyEpoch: challenge.keyEpoch,
            deviceID: deviceID,
            bootstrap: bootstrap,
            keys: keys,
            enrolledAt: enrolledAt,
            pkceChallenge: grant.codeChallenge,
            state: grant.state
        ))
        let receiptData = try await submitEnrollment(enrollment, accessToken: accessToken)
        try remoteCommandFinalizer.install(receiptData: receiptData)

        let localEnrollment = AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: challenge.keyEpoch,
            enrolledAt: enrolledAt
        )
        let recoveryEnvelope = AccountRecoveryEnvelopeBridge.generated(bootstrap.recoveryEnvelope)
        let uploaded = try await uploadRecoveryEnvelope(
            recoveryEnvelope,
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: keys.signingPrivateKey
        )
        if uploaded {
            return .saveRecoveryKey(bootstrap.recoveryKey, localEnrollment)
        }
        return .enterRecoveryKey(localEnrollment)
    }

    private func submitEnrollment(
        _ enrollment: DeviceEnrollmentRequest,
        accessToken: String
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: "/sync/devices/enroll"))
        request.httpMethod = "POST"
        request.httpBody = try enrollment.jsonData()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await responseData(for: request, acceptedStatuses: 200 ..< 300)
    }

    func restore(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> AccountDeviceEnrollment {
        guard let tokenData = try secretStore.data(for: "oauth-access-token"),
              let accessToken = String(data: tokenData, encoding: .utf8),
              let keys = try keyStore.load(deviceID: enrollment.deviceID)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        let endpoint = baseURL.appending(path: "/sync/e2ee/recovery-envelope")
        let challenge = try await challenge(
            deviceID: enrollment.deviceID,
            accessToken: accessToken
        )
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: challenge.coordinatorNonce,
            method: "GET",
            url: endpoint,
            body: nil,
            signingPrivateKey: keys.signingPrivateKey
        ))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(
            enrollment.deviceID.uuidString.lowercased(),
            forHTTPHeaderField: "X-Curfew-Device-ID"
        )
        let data = try await responseData(for: request, acceptedStatuses: 200 ..< 300)
        let generated = try RecoveryKeyEnvelope(data: data)
        let local = try AccountRecoveryEnvelopeBridge.local(generated)
        let rootKey = try AccountRecoveryCrypto.unwrap(local, recoveryKey: recoveryKey)
        try keyStore.replaceAccountRootKey(rootKey, deviceID: enrollment.deviceID)
        return enrollment
    }

    private func uploadRecoveryEnvelope(
        _ envelope: RecoveryKeyEnvelope,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Bool {
        let endpoint = baseURL.appending(path: "/sync/e2ee/recovery-envelope")
        let body = try envelope.jsonData()
        let challenge = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: challenge.coordinatorNonce,
            method: "PUT",
            url: endpoint,
            body: body,
            signingPrivateKey: signingPrivateKey
        ))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(
            deviceID.uuidString.lowercased(),
            forHTTPHeaderField: "X-Curfew-Device-ID"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        if response.statusCode == 409 {
            return false
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        return true
    }

    private func challenge(
        deviceID: UUID,
        accessToken: String
    ) async throws -> NativeDeviceProofChallenge {
        let endpoint = baseURL.appending(path: "/sync/device-proof/challenge")
        let body = try JSONSerialization.data(
            withJSONObject: ["deviceId": deviceID.uuidString.lowercased()]
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await responseData(for: request, acceptedStatuses: 200 ..< 300)
        return try JSONDecoder().decode(NativeDeviceProofChallenge.self, from: data)
    }

    private func responseData(
        for request: URLRequest,
        acceptedStatuses: Range<Int>
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              acceptedStatuses.contains(response.statusCode),
              data.count <= 32 * 1024
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return data
    }
}
