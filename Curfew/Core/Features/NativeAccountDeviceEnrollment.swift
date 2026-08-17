import Combine
import CurfewProtocols
import Foundation

struct AccountDeviceEnrollmentRequestInput {
    let accessToken: String
    let nonce: String
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
            keyEpoch: 1,
            pkceChallenge: input.pkceChallenge,
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
            keyEpoch: 1,
            pkceChallenge: input.pkceChallenge,
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

enum NativeAccountEnrollmentState: Equatable {
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
}

enum AccountEnrollmentUIState: Equatable {
    case accountFree
    case signingIn
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
    case ready(AccountDeviceEnrollment)
    case failed(String)
}

final class AccountEnrollmentPendingStore {
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func save(enrollment: AccountDeviceEnrollment, recoveryKey: String?) throws {
        try secretStore.save(
            JSONEncoder().encode(enrollment),
            for: "pending-account-enrollment"
        )
        if let recoveryKey {
            try secretStore.save(Data(recoveryKey.utf8), for: "pending-recovery-key")
        } else {
            try secretStore.delete("pending-recovery-key")
        }
    }

    func load() throws -> AccountEnrollmentUIState? {
        guard let data = try secretStore.data(for: "pending-account-enrollment") else {
            return nil
        }
        let enrollment = try JSONDecoder().decode(AccountDeviceEnrollment.self, from: data)
        if let keyData = try secretStore.data(for: "pending-recovery-key"),
           let key = String(data: keyData, encoding: .utf8),
           !key.isEmpty {
            return .saveRecoveryKey(key, enrollment)
        }
        return .enterRecoveryKey(enrollment)
    }

    func clear() throws {
        try secretStore.delete("pending-account-enrollment")
        try secretStore.delete("pending-recovery-key")
    }
}

@MainActor
final class AccountEnrollmentController: ObservableObject {
    @Published private(set) var state: AccountEnrollmentUIState = .accountFree

    private let secretStore: any AccountSecretStoring
    private let oauth: AccountOAuthEnrollmentService
    private let devices: NativeAccountDeviceEnrollmentService
    private let pending: AccountEnrollmentPendingStore

    init(secretStore: any AccountSecretStoring = KeychainAccountSecretStore()) {
        self.secretStore = secretStore
        self.oauth = AccountOAuthEnrollmentService(secretStore: secretStore)
        self.devices = NativeAccountDeviceEnrollmentService(secretStore: secretStore)
        self.pending = AccountEnrollmentPendingStore(secretStore: secretStore)
        self.state = (try? pending.load()) ?? .accountFree
    }

    func signIn() async {
        state = .signingIn
        do {
            let grant = try await oauth.signIn()
            let outcome = try await devices.enroll(
                grant: grant,
                deviceID: deviceID()
            )
            switch outcome {
            case .saveRecoveryKey(let key, let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: key)
                state = .saveRecoveryKey(key, enrollment)
            case .enterRecoveryKey(let enrollment):
                try pending.save(enrollment: enrollment, recoveryKey: nil)
                state = .enterRecoveryKey(enrollment)
            }
        } catch {
            state = .failed("Account sign-in or encrypted device enrollment failed.")
        }
    }

    func restore(recoveryKey: String) async {
        guard case .enterRecoveryKey(let enrollment) = state else { return }
        do {
            let restored = try await devices.restore(
                recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines),
                enrollment: enrollment
            )
            try pending.clear()
            state = .ready(restored)
        } catch {
            state = .failed("That Recovery Key could not decrypt this Curfew account.")
        }
    }

    func acknowledgeSavedRecoveryKey() throws -> AccountDeviceEnrollment? {
        guard case .saveRecoveryKey(_, let enrollment) = state else { return nil }
        try pending.clear()
        state = .ready(enrollment)
        return enrollment
    }

    private func deviceID() throws -> UUID {
        if let data = try secretStore.data(for: "account-device-id"),
           let text = String(data: data, encoding: .utf8),
           let identifier = UUID(uuidString: text) {
            return identifier
        }
        let identifier = UUID()
        try secretStore.save(
            Data(identifier.uuidString.lowercased().utf8),
            for: "account-device-id"
        )
        return identifier
    }
}

@MainActor
final class NativeAccountDeviceEnrollmentService {
    private struct Challenge: Decodable { let nonce: String }

    private let secretStore: any AccountSecretStoring
    private let keyStore: AccountDeviceKeyStore
    private let session: URLSession
    private let proofFactory: AccountDeviceProofFactory
    private let baseURL = URL(string: "https://curfew-sync.hypertext.studio")!

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory = AccountDeviceProofFactory()
    ) {
        self.secretStore = secretStore
        self.keyStore = AccountDeviceKeyStore(secretStore: secretStore)
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
        self.proofFactory = proofFactory
    }

    func enroll(
        grant: AccountOAuthGrant,
        deviceID: UUID,
        enrolledAt: Date = Date()
    ) async throws -> NativeAccountEnrollmentState {
        let bootstrap = try keyStore.createEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
            createdAt: enrolledAt
        )
        guard let keys = try keyStore.load(deviceID: deviceID) else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        let accessToken = grant.tokens.accessToken
        let nonce = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let enrollment = try AccountDeviceEnrollmentRequestBuilder(
            proofFactory: proofFactory
        ).make(AccountDeviceEnrollmentRequestInput(
            accessToken: accessToken,
            nonce: nonce,
            deviceID: deviceID,
            bootstrap: bootstrap,
            keys: keys,
            enrolledAt: enrolledAt,
            pkceChallenge: grant.codeChallenge,
            state: grant.state
        ))
        var enrollmentRequest = URLRequest(
            url: baseURL.appending(path: "/sync/devices/enroll")
        )
        enrollmentRequest.httpMethod = "POST"
        enrollmentRequest.httpBody = try enrollment.jsonData()
        enrollmentRequest.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        enrollmentRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await responseData(for: enrollmentRequest, acceptedStatuses: 200 ..< 300)

        let localEnrollment = AccountDeviceEnrollment(
            deviceID: deviceID,
            keyEpoch: 1,
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

    func restore(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> AccountDeviceEnrollment {
        guard let tokenData = try secretStore.data(for: "oauth-access-token"),
              let accessToken = String(data: tokenData, encoding: .utf8),
              let keys = try keyStore.load(deviceID: enrollment.deviceID)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        let endpoint = baseURL.appending(path: "/sync/e2ee/recovery-envelope")
        let nonce = try await challenge(
            deviceID: enrollment.deviceID,
            accessToken: accessToken
        )
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: nonce,
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
        let nonce = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: nonce,
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

    private func challenge(deviceID: UUID, accessToken: String) async throws -> String {
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
        return try JSONDecoder().decode(Challenge.self, from: data).nonce
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
