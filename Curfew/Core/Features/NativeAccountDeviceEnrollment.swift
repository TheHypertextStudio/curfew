import CurfewProtocols
import Foundation

// Enrollment and its crash-recovery state machine stay in one review unit so
// checkpoint ordering cannot drift from the network operations it protects.
// swiftlint:disable file_length

enum NativeAccountEnrollmentState: Equatable {
    case finishDeviceRegistration(String, AccountDeviceEnrollment)
    case finishRecoverySetup(String, AccountDeviceEnrollment)
    case saveRecoveryKey(String, AccountDeviceEnrollment)
    case enterRecoveryKey(AccountDeviceEnrollment)
}

@MainActor
// swiftlint:disable:next type_body_length
final class NativeAccountDeviceEnrollmentService {
    private let secretStore: any AccountSecretStoring
    private let keyStore: AccountDeviceKeyStore
    private let session: URLSession
    private let tokenRefresher: AccountOAuthTokenRefresher
    private let proofFactory: AccountDeviceProofFactory
    private let remoteCommandFinalizer: RemoteCommandEnrollmentFinalizer
    private let pending: AccountEnrollmentPendingStore
    private let baseURL: URL

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory = AccountDeviceProofFactory(),
        endpoints: CurfewServiceEndpoints = .current,
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
        self.baseURL = endpoints.syncResource
        self.tokenRefresher = AccountOAuthTokenRefresher(
            secretStore: secretStore,
            session: self.session,
            endpoints: endpoints
        )
        self.pending = AccountEnrollmentPendingStore(secretStore: secretStore)
        self.remoteCommandFinalizer = RemoteCommandEnrollmentFinalizer(
            store: remoteCommandEnrollmentStore
        )
    }

    func enroll(
        grant: AccountOAuthGrant,
        deviceID: UUID,
        enrolledAt: Date = Date()
    ) async throws -> NativeAccountEnrollmentState {
        let prepared = try await prepareRegistration(
            grant: grant,
            deviceID: deviceID,
            enrolledAt: enrolledAt
        )
        try pending.saveDeviceRegistration(
            enrollment: prepared.localEnrollment,
            recoveryKey: prepared.bootstrap.recoveryKey,
            recoveryEnvelope: prepared.recoveryEnvelope,
            oauthState: grant.state,
            pkceChallenge: grant.codeChallenge
        )
        let receiptData: Data
        do {
            receiptData = try await submitEnrollment(
                prepared.request,
                accessToken: grant.tokens.accessToken
            )
            try pending.saveRegistrationReceipt(receiptData)
        } catch {
            return .finishDeviceRegistration(
                prepared.bootstrap.recoveryKey,
                prepared.localEnrollment
            )
        }
        do {
            return try await completeRecoverySetup(
                recoverySetupCheckpoint(
                    recoveryKey: prepared.bootstrap.recoveryKey,
                    enrollment: prepared.localEnrollment
                )
            )
        } catch {
            return .finishRecoverySetup(
                prepared.bootstrap.recoveryKey,
                prepared.localEnrollment
            )
        }
    }

    func resumeDeviceRegistration(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        let checkpoint = try recoverySetupCheckpoint(
            recoveryKey: recoveryKey,
            enrollment: enrollment
        )
        guard checkpoint.receiptData == nil,
              let keys = try keyStore.load(deviceID: enrollment.deviceID)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        let receiptData = try await withRefreshingAccessToken { accessToken in
            let challenge = try await self.challenge(
                deviceID: enrollment.deviceID,
                accessToken: accessToken
            )
            guard challenge.keyEpoch == enrollment.keyEpoch else {
                throw AccountOAuthEnrollmentError.invalidResponse
            }
            let bootstrap = try AccountEnrollmentBootstrap(
                recoveryKey: checkpoint.recoveryKey,
                recoveryEnvelope: AccountRecoveryEnvelopeBridge.local(
                    checkpoint.recoveryEnvelope
                ),
                encryptionPublicKey: keys.encryptionPublicKey,
                signingPublicKey: keys.signingPublicKey
            )
            let request = try AccountDeviceEnrollmentRequestBuilder(
                proofFactory: self.proofFactory
            ).make(AccountDeviceEnrollmentRequestInput(
                accessToken: accessToken,
                nonce: challenge.coordinatorNonce,
                keyEpoch: challenge.keyEpoch,
                deviceID: enrollment.deviceID,
                bootstrap: bootstrap,
                keys: keys,
                enrolledAt: enrollment.enrolledAt,
                pkceChallenge: checkpoint.pkceChallenge,
                state: checkpoint.oauthState,
                syncResource: self.baseURL
            ))
            return try await self.submitEnrollment(request, accessToken: accessToken)
        }
        try pending.saveRegistrationReceipt(receiptData)
        do {
            return try await completeRecoverySetup(
                recoverySetupCheckpoint(recoveryKey: recoveryKey, enrollment: enrollment)
            )
        } catch {
            return .finishRecoverySetup(recoveryKey, enrollment)
        }
    }

    func resumeRecoverySetup(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> NativeAccountEnrollmentState {
        try await completeRecoverySetup(
            recoverySetupCheckpoint(
                recoveryKey: recoveryKey,
                enrollment: enrollment
            )
        )
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

    private func prepareRegistration(
        grant: AccountOAuthGrant,
        deviceID: UUID,
        enrolledAt: Date
    ) async throws -> PreparedDeviceRegistration {
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
        let request = try AccountDeviceEnrollmentRequestBuilder(
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
            state: grant.state,
            syncResource: baseURL
        ))
        return PreparedDeviceRegistration(
            request: request,
            localEnrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: challenge.keyEpoch,
                enrolledAt: enrolledAt
            ),
            bootstrap: bootstrap,
            recoveryEnvelope: AccountRecoveryEnvelopeBridge.generated(
                bootstrap.recoveryEnvelope
            )
        )
    }

    func restore(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) async throws -> AccountDeviceEnrollment {
        guard let keys = try keyStore.load(deviceID: enrollment.deviceID)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        let data = try await withRefreshingAccessToken { accessToken in
            let endpoint = self.baseURL.appending(path: "/sync/e2ee/recovery-envelope")
            let challenge = try await self.challenge(
                deviceID: enrollment.deviceID,
                accessToken: accessToken
            )
            let proof = try self.proofFactory.make(.init(
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
            return try await self.responseData(for: request, acceptedStatuses: 200 ..< 300)
        }
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
            throw NativeAccountSyncError.rejected(response.statusCode)
        }
        return true
    }
}

private extension NativeAccountDeviceEnrollmentService {
    func recoverySetupCheckpoint(
        recoveryKey: String,
        enrollment: AccountDeviceEnrollment
    ) throws -> AccountRecoverySetupCheckpoint {
        guard let checkpoint = try pending.loadRecoverySetup(),
              checkpoint.recoveryKey == recoveryKey,
              checkpoint.enrollment == enrollment
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return checkpoint
    }

    func completeRecoverySetup(
        _ checkpoint: AccountRecoverySetupCheckpoint
    ) async throws -> NativeAccountEnrollmentState {
        guard let receiptData = checkpoint.receiptData,
              let keys = try keyStore.load(deviceID: checkpoint.enrollment.deviceID)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        try remoteCommandFinalizer.install(receiptData: receiptData)
        let recoveryEnvelopeIsOurs = try await withRefreshingAccessToken { accessToken in
            let uploaded = try await self.uploadRecoveryEnvelope(
                checkpoint.recoveryEnvelope,
                deviceID: checkpoint.enrollment.deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            )
            if uploaded {
                return true
            }
            return try await self.storedRecoveryEnvelopeMatches(
                checkpoint.recoveryEnvelope,
                deviceID: checkpoint.enrollment.deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            )
        }
        if recoveryEnvelopeIsOurs {
            try pending.save(
                enrollment: checkpoint.enrollment,
                recoveryKey: checkpoint.recoveryKey
            )
            return .saveRecoveryKey(checkpoint.recoveryKey, checkpoint.enrollment)
        }
        try pending.save(enrollment: checkpoint.enrollment, recoveryKey: nil)
        return .enterRecoveryKey(checkpoint.enrollment)
    }

    func storedRecoveryEnvelopeMatches(
        _ expected: RecoveryKeyEnvelope,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Bool {
        let endpoint = baseURL.appending(path: "/sync/e2ee/recovery-envelope")
        let challenge = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: challenge.coordinatorNonce,
            method: "GET",
            url: endpoint,
            body: nil,
            signingPrivateKey: signingPrivateKey
        ))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(deviceID.uuidString.lowercased(), forHTTPHeaderField: "X-Curfew-Device-ID")
        let data = try await responseData(for: request, acceptedStatuses: 200 ..< 300)
        let stored = try RecoveryKeyEnvelope(data: data)
        return try canonicalJSON(stored.jsonData()) == canonicalJSON(expected.jsonData())
    }

    func challenge(
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

    func responseData(
        for request: URLRequest,
        acceptedStatuses: Range<Int>
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        guard acceptedStatuses.contains(response.statusCode) else {
            throw NativeAccountSyncError.rejected(response.statusCode)
        }
        guard data.count <= 32 * 1024 else {
            throw AccountOAuthEnrollmentError.invalidResponse
        }
        return data
    }

    func withRefreshingAccessToken<T>(
        _ operation: (String) async throws -> T
    ) async throws -> T {
        func accessToken() throws -> String {
            guard let data = try secretStore.data(for: "oauth-access-token"),
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty
            else { throw AccountOAuthEnrollmentError.invalidResponse }
            return token
        }
        do {
            return try await operation(accessToken())
        } catch NativeAccountSyncError.rejected(401) {
            try await tokenRefresher.refresh()
            return try await operation(accessToken())
        }
    }

    func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
