import CryptoKit
import CurfewProtocols
import Foundation

enum NativeAccountSyncError: Error {
    case missingCredentials
    case invalidResponse
    case rejected(Int)
}

struct NativeDeviceProofChallenge: Decodable {
    let coordinatorNonce: String
    let keyEpoch: Int
}

struct AccountDeviceProofFactory {
    struct Input {
        let accessToken: String
        let nonce: String
        let method: String
        let url: URL
        let body: Data?
        let signingPrivateKey: Data
    }

    let now: () -> Date
    let identifier: () -> UUID

    init(
        now: @escaping () -> Date = Date.init,
        identifier: @escaping () -> UUID = UUID.init
    ) {
        self.now = now
        self.identifier = identifier
    }

    func make(_ input: Input) throws -> String {
        let bodyDigest = try input.body.map { data -> String in
            let value = try JSONSerialization.jsonObject(with: data)
            let canonical = try JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            return Self.base64URL(Data(SHA256.hash(data: canonical)))
        }
        let claims = DeviceProofClaims(
            accessTokenHash: Self.base64URL(
                Data(SHA256.hash(data: Data(input.accessToken.utf8)))
            ),
            bodyDigest: bodyDigest,
            canonicalURL: input.url.absoluteString,
            httpMethod: input.method,
            issuedAt: Self.dateFormatter.string(from: now()),
            jti: identifier().uuidString.lowercased(),
            nonce: input.nonce
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let header = Self.base64URL(Data(#"{"alg":"ES256","typ":"curfew-device-proof+jws"}"#.utf8))
        let payload = try Self.base64URL(encoder.encode(claims))
        let signingInput = "\(header).\(payload)"
        let key = try P256.Signing.PrivateKey(rawRepresentation: input.signingPrivateKey)
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        return "\(signingInput).\(Self.base64URL(signature))"
    }

    private static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

@MainActor
final class NativeAccountSyncTransport: AccountSyncTransporting {
    private let secretStore: any AccountSecretStoring
    private let keyStore: AccountDeviceKeyStore
    private let tokenRefresher: AccountOAuthTokenRefresher
    private let authorizedHTTP: NativeAccountAuthorizedHTTPClient
    private let inboxStore: RemoteCommandInboxStore
    private let resultExchangeStore: RemoteCommandResultExchangeStore
    private let enrollmentStore: RemoteCommandEnrollmentStore
    private let pollingInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var overridePollingTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Error>?
    private var onWakeStatus: ((AccountWakeStatusUpdate) -> Void)?
    private var onRemoteOverride: ((AccountRemoteOverride?) -> Void)?
    private var onRemoteCommandResult: ((RemoteCommandResult) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var distributedPeerEpochs: Set<String> = []

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory? = nil,
        inboxStore: RemoteCommandInboxStore? = nil,
        resultExchangeStore: RemoteCommandResultExchangeStore? = nil,
        enrollmentStore: RemoteCommandEnrollmentStore? = nil,
        pollingInterval: Duration = .seconds(15)
    ) {
        self.secretStore = secretStore
        self.keyStore = AccountDeviceKeyStore(secretStore: secretStore)
        let resolvedSession = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
        self.authorizedHTTP = NativeAccountAuthorizedHTTPClient(
            session: resolvedSession,
            proofFactory: proofFactory ?? AccountDeviceProofFactory()
        )
        self.tokenRefresher = AccountOAuthTokenRefresher(
            secretStore: secretStore,
            session: resolvedSession
        )
        self.inboxStore = inboxStore ?? RemoteCommandInboxStore(
            directoryURL: SharedPaths.remoteCommandInbox
        )
        self.resultExchangeStore = resultExchangeStore ?? RemoteCommandResultExchangeStore(
            resultsURL: SharedPaths.remoteCommandResults,
            acknowledgementsDirectoryURL: SharedPaths.remoteCommandResultAcknowledgements,
            requiredDirectoryOwnerUserID: 0
        )
        self.enrollmentStore = enrollmentStore ?? RemoteCommandEnrollmentStore(
            recordURL: SharedPaths.remoteCommandEnrollment
        )
        self.pollingInterval = pollingInterval
    }
}

@MainActor
extension NativeAccountSyncTransport {
    func connect(
        deviceID: UUID,
        onWakeStatus: @escaping (AccountWakeStatusUpdate) -> Void,
        onRemoteOverride: @escaping (AccountRemoteOverride?) -> Void,
        onRemoteCommandResult: @escaping (RemoteCommandResult) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        disconnect()
        self.onWakeStatus = onWakeStatus
        self.onRemoteOverride = onRemoteOverride
        self.onRemoteCommandResult = onRemoteCommandResult
        self.onFailure = onFailure
        overridePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollRemoteOverrideOnce(deviceID: deviceID)
                guard let interval = self?.pollingInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAccountStateOnce(deviceID: deviceID)
                guard let interval = self?.pollingInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        overridePollingTask?.cancel()
        overridePollingTask = nil
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        do {
            try enrollmentStore.recordEligibility(
                statusVersion: report.statusVersion,
                scheduleDigest: report.scheduleDigest
            )
        } catch {
            onFailure?("Remote control is waiting for this Mac to finish enrollment.")
            return
        }
        Task { [weak self] in
            do {
                guard let self,
                      let tokenData = try secretStore.data(for: "oauth-access-token"),
                      let accessToken = String(data: tokenData, encoding: .utf8),
                      let keys = try keyStore.load(deviceID: deviceID)
                else { throw NativeAccountSyncError.missingCredentials }
                try await authorizedHTTP.post(
                    path: "/sync/status",
                    body: report.encodedBody(),
                    deviceID: deviceID,
                    accessToken: accessToken,
                    signingPrivateKey: keys.signingPrivateKey
                )
            } catch {
                self?.onFailure?("Device status publication is offline or rejected.")
            }
        }
    }

    func pollOnce(deviceID: UUID) async {
        await pollRemoteOverrideOnce(deviceID: deviceID)
        await pollAccountStateOnce(deviceID: deviceID)
    }

    private func pollRemoteOverrideOnce(deviceID: UUID) async {
        await pollWithRefresh(deviceID: deviceID) { [self] in
            try await onRemoteOverride?(fetchRemoteOverride(deviceID: deviceID))
        }
    }

    private func pollAccountStateOnce(deviceID: UUID) async {
        await pollWithRefresh(deviceID: deviceID) { [self] in
            try await pollAccountStateWithCurrentCredentials(deviceID: deviceID)
        }
    }

    private func pollWithRefresh(
        deviceID _: UUID,
        operation: @MainActor () async throws -> Void
    ) async {
        let rejectedAccessToken = try? storedAccessToken()
        do {
            try await operation()
        } catch NativeAccountSyncError.rejected(401) {
            do {
                try await refreshAccessToken(rejectedAccessToken: rejectedAccessToken)
                try await operation()
            } catch {
                onFailure?("Account sync is offline or rejected.")
            }
        } catch {
            onFailure?("Account sync is offline or rejected.")
        }
    }

    private func refreshAccessToken(rejectedAccessToken: String?) async throws {
        if let rejectedAccessToken,
           try storedAccessToken() != rejectedAccessToken {
            return
        }
        if let tokenRefreshTask {
            try await tokenRefreshTask.value
            return
        }
        let task = Task { [tokenRefresher] in
            try await tokenRefresher.refresh()
        }
        tokenRefreshTask = task
        defer { tokenRefreshTask = nil }
        try await task.value
    }

    private func storedAccessToken() throws -> String {
        guard let tokenData = try secretStore.data(for: "oauth-access-token"),
              let accessToken = String(data: tokenData, encoding: .utf8)
        else { throw NativeAccountSyncError.missingCredentials }
        return accessToken
    }

    private func currentCredentials(
        deviceID: UUID
    ) throws -> (accessToken: String, keys: AccountDeviceKeyMaterial) {
        guard let keys = try keyStore.load(deviceID: deviceID)
        else { throw NativeAccountSyncError.missingCredentials }
        return try (storedAccessToken(), keys)
    }

    func fetchRemoteOverride(deviceID: UUID) async throws -> AccountRemoteOverride? {
        let credentials = try currentCredentials(deviceID: deviceID)
        return try await authorizedHTTP.get(
            path: "/sync/remote-overrides/active",
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ).map { data in
            try Self.remoteOverride(RemoteOverride(data: data))
        }
    }

    private func pollAccountStateWithCurrentCredentials(deviceID: UUID) async throws {
        let credentials = try currentCredentials(deviceID: deviceID)

        try await publishPendingRemoteCommandResults(
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        )

        do {
            try await distributeRootKey(
                deviceID: deviceID,
                accessToken: credentials.accessToken,
                keys: credentials.keys
            )
        } catch NativeAccountSyncError.rejected(401) {
            throw NativeAccountSyncError.rejected(401)
        } catch {
            onFailure?("Encrypted device-key distribution is offline or rejected.")
        }

        if let data = try await authorizedHTTP.get(
            path: "/sync/wake/status",
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ) {
            try onWakeStatus?(Self.wakeStatus(WakeStatus(data: data)))
        }
        if let data = try await authorizedHTTP.get(
            path: "/sync/remote-control/commands",
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ) {
            for delivery in try Self.remoteCommandDeliveries(
                RemoteCommandDeliveryBatch(data: data)
            ) {
                try inboxStore.stage(delivery)
            }
        }
    }

    private func publishPendingRemoteCommandResults(
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws {
        for result in try resultExchangeStore.pendingResults() {
            guard result.deviceID == deviceID else {
                throw NativeAccountSyncError.invalidResponse
            }
            onRemoteCommandResult?(result)
            let wire = try Self.remoteCommandResult(result)
            let response = try await authorizedHTTP.post(
                path: "/sync/remote-control/commands/result",
                body: wire.jsonData(),
                deviceID: deviceID,
                accessToken: accessToken,
                signingPrivateKey: signingPrivateKey
            )
            let receipt = try CurfewProtocols.SignedRemoteCommandResultReceiptEnvelope
                .decodeValidated(response)
            try resultExchangeStore.recordReceipt(
                CoordinatorSignedRemoteCommandResultReceiptEnvelope(
                    compactJWS: receipt.compactJws
                ),
                for: result
            )
        }
    }

    private func distributeRootKey(
        deviceID: UUID,
        accessToken: String,
        keys: AccountDeviceKeyMaterial
    ) async throws {
        guard let data = try await authorizedHTTP.get(
            path: "/sync/devices",
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: keys.signingPrivateKey
        ) else { return }
        let devices = try JSONDecoder().decode(
            [CurfewProtocols.AccountDeviceEnrollment].self,
            from: data
        )
        for peer in devices where peer.deviceID != deviceID.uuidString.lowercased() {
            let fingerprint = "\(peer.deviceID):\(peer.keyEpoch):\(peer.enrolledAt)"
            guard !distributedPeerEpochs.contains(fingerprint) else { continue }
            let envelope = try AccountRootKeyEnvelopeCrypto.seal(
                rootKey: keys.accountRootKey,
                recipient: peer,
                createdAt: Date()
            )
            try await authorizedHTTP.put(
                path: "/sync/devices/\(peer.deviceID)/root-key-envelope",
                body: envelope.jsonData(),
                deviceID: deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            )
            distributedPeerEpochs.insert(fingerprint)
        }
    }
}
