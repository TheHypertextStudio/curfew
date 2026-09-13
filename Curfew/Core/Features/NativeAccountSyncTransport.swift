import CurfewProtocols
import Foundation

enum NativeAccountSyncError: Error {
    case missingCredentials
    case invalidResponse
    case rejected(Int)
}

enum AccountHealthChannel: Hashable {
    case accountState
    case deviceStatus
    case remoteOverride
}

struct NativeDeviceProofChallenge: Decodable {
    let coordinatorNonce: String
    let keyEpoch: Int
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
    let now: () -> Date
    private var pollingTask: Task<Void, Never>?
    private var overridePollingTask: Task<Void, Never>?
    private var tokenRefreshTask: Task<Void, Error>?
    var onSynchronized: ((Date) -> Void)?
    var onOffline: (() -> Void)?
    private var onWakeStatus: ((AccountWakeStatusUpdate) -> Void)?
    private var onRemoteOverride: ((AccountRemoteOverride?) -> Void)?
    private var onRemoteCommandResult: ((RemoteCommandResult) -> Void)?
    var onFailure: ((String) -> Void)?
    var healthyChannels: Set<AccountHealthChannel> = []
    var requiredChannels: Set<AccountHealthChannel> = [.accountState, .remoteOverride]
    var connectionGeneration = 0
    private var deviceStatusGeneration = 0
    private var distributedPeerEpochs: Set<String> = []

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory? = nil,
        inboxStore: RemoteCommandInboxStore? = nil,
        resultExchangeStore: RemoteCommandResultExchangeStore? = nil,
        enrollmentStore: RemoteCommandEnrollmentStore? = nil,
        pollingInterval: Duration = .seconds(15),
        now: @escaping () -> Date = Date.init
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
        self.now = now
    }
}

@MainActor
extension NativeAccountSyncTransport {
    func connect(deviceID: UUID, callbacks: AccountSyncTransportCallbacks) {
        disconnect()
        onSynchronized = callbacks.onSynchronized
        onOffline = callbacks.onOffline
        onWakeStatus = callbacks.onWakeStatus
        onRemoteOverride = callbacks.onRemoteOverride
        onRemoteCommandResult = callbacks.onRemoteCommandResult
        onFailure = callbacks.onFailure
        let generation = connectionGeneration
        overridePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollRemoteOverrideOnce(deviceID: deviceID, generation: generation)
                guard let interval = self?.pollingInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollAccountStateOnce(deviceID: deviceID, generation: generation)
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
        onSynchronized = nil
        onOffline = nil
        onWakeStatus = nil
        onRemoteOverride = nil
        onRemoteCommandResult = nil
        onFailure = nil
        healthyChannels.removeAll()
        requiredChannels = [.accountState, .remoteOverride]
        connectionGeneration += 1
        deviceStatusGeneration += 1
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        requiredChannels.insert(.deviceStatus)
        deviceStatusGeneration += 1
        let generation = deviceStatusGeneration
        do {
            try enrollmentStore.recordEligibility(
                statusVersion: report.statusVersion,
                scheduleDigest: report.scheduleDigest
            )
        } catch {
            recordOperationFailure(
                NativeAccountSyncError.missingCredentials,
                channel: .deviceStatus
            )
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
                guard generation == deviceStatusGeneration else { return }
                recordSuccessfulOperation(.deviceStatus)
            } catch {
                guard let self, generation == deviceStatusGeneration else { return }
                recordOperationFailure(error, channel: .deviceStatus)
            }
        }
    }

    func pollOnce(deviceID: UUID) async {
        let generation = connectionGeneration
        await pollRemoteOverrideOnce(deviceID: deviceID, generation: generation)
        await pollAccountStateOnce(deviceID: deviceID, generation: generation)
    }

    private func pollRemoteOverrideOnce(deviceID: UUID, generation: Int) async {
        await pollWithRefresh(
            deviceID: deviceID,
            channel: .remoteOverride,
            generation: generation
        ) { [self] in
            let remoteOverride = try await fetchRemoteOverride(deviceID: deviceID)
            guard isCurrentConnection(generation) else { return }
            onRemoteOverride?(remoteOverride)
        }
    }

    private func pollAccountStateOnce(deviceID: UUID, generation: Int) async {
        await pollWithRefresh(
            deviceID: deviceID,
            channel: .accountState,
            generation: generation
        ) { [self] in
            try await pollAccountStateWithCurrentCredentials(
                deviceID: deviceID,
                generation: generation
            )
        }
    }

    private func pollWithRefresh(
        deviceID _: UUID,
        channel: AccountHealthChannel,
        generation: Int,
        operation: @MainActor () async throws -> Void
    ) async {
        let rejectedAccessToken = try? storedAccessToken()
        do {
            try await operation()
            guard isCurrentConnection(generation) else { return }
            recordSuccessfulOperation(channel)
        } catch NativeAccountSyncError.rejected(401) {
            do {
                try await refreshAccessToken(rejectedAccessToken: rejectedAccessToken)
                guard isCurrentConnection(generation) else { return }
                try await operation()
                guard isCurrentConnection(generation) else { return }
                recordSuccessfulOperation(channel)
            } catch {
                guard isCurrentConnection(generation) else { return }
                recordPollFailure(error, channel: channel)
            }
        } catch {
            guard isCurrentConnection(generation) else { return }
            recordPollFailure(error, channel: channel)
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

    private func pollAccountStateWithCurrentCredentials(
        deviceID: UUID,
        generation: Int
    ) async throws {
        let credentials = try currentCredentials(deviceID: deviceID)

        try await publishPendingRemoteCommandResults(
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey,
            generation: generation
        )

        try await distributeRootKey(
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            keys: credentials.keys
        )
        guard isCurrentConnection(generation) else { return }

        if let data = try await authorizedHTTP.get(
            path: "/sync/wake/status",
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ) {
            guard isCurrentConnection(generation) else { return }
            try onWakeStatus?(Self.wakeStatus(WakeStatus(data: data)))
        }
        if let data = try await authorizedHTTP.get(
            path: "/sync/remote-control/commands",
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ) {
            guard isCurrentConnection(generation) else { return }
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
        signingPrivateKey: Data,
        generation: Int
    ) async throws {
        for result in try resultExchangeStore.pendingResults() {
            guard isCurrentConnection(generation) else { return }
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
            guard isCurrentConnection(generation) else { return }
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
