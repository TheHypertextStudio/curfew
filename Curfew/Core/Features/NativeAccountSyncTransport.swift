import CurfewKit
import CurfewProtocols
import Foundation

extension AccountSyncEngine {
    convenience init() {
        self.init(transport: NativeAccountSyncTransport())
    }
}

enum NativeAccountSyncError: Error {
    case missingCredentials
    case invalidResponse
    case rejected(Int)
}

enum AccountHealthChannel: Hashable {
    case accountState
    case deviceStatus
    case remoteOverride
    case remoteCommands
    case peerDevices
    case commandResults
}

struct NativeDeviceProofChallenge: Decodable {
    let coordinatorNonce: String
    let keyEpoch: Int
}

@MainActor
final class NativeAccountSyncTransport: AccountSyncTransporting {
    let secretStore: any AccountSecretStoring
    let keyStore: AccountDeviceKeyStore
    let tokenRefresher: AccountOAuthTokenRefresher
    let authorizedHTTP: NativeAccountAuthorizedHTTPClient
    let inboxStore: RemoteCommandInboxStore
    let resultExchangeStore: RemoteCommandResultExchangeStore
    private let enrollmentStore: RemoteCommandEnrollmentStore
    private let pollingInterval: Duration?
    private let socketEnabled: Bool
    private let clock = ContinuousClock()
    private var startedAt = ContinuousClock.now
    private var reconciliation = AccountSyncReconciliationSchedule()
    private var reconciliationTasks: [
        AccountSyncReconciliationSchedule.Channel: Task<Void, Never>
    ] =
        [:]
    private var socket: AccountSyncSocket?
    private var connectivityObserver: NativeAccountSyncConnectivityObserver?
    let now: () -> Date
    private var pollingTask: Task<Void, Never>?
    var tokenRefreshTask: Task<Void, Error>?
    var tokenRefreshGeneration = 0
    var resultPublicationTask: Task<Void, Error>?
    var resultPublicationGeneration = 0
    var publishedResults: [(
        result: CurfewKit.RemoteCommandResult,
        receipt: CoordinatorSignedRemoteCommandResultReceiptEnvelope
    )] = []
    private var statusPublicationTask: Task<Void, Never>?
    private var statusPublications = AccountStatusPublicationLedger()
    var onSynchronized: ((Date) -> Void)?
    var onOffline: (() -> Void)?
    var onWakeStatus: ((AccountWakeStatusUpdate) -> Void)?
    var onRemoteOverride: ((AccountRemoteOverride?) -> Void)?
    var onRemoteCommandResult: ((CurfewKit.RemoteCommandResult) -> Void)?
    var onFailure: ((String) -> Void)?
    var healthyChannels: Set<AccountHealthChannel> = []
    var requiredChannels: Set<AccountHealthChannel> = [
        .accountState,
        .remoteOverride,
        .remoteCommands,
        .peerDevices
    ]
    var connectionGeneration = 0
    private var deviceStatusGeneration = 0
    var distributedPeerEpochs: Set<String> = []

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory? = nil,
        inboxStore: RemoteCommandInboxStore? = nil,
        resultExchangeStore: RemoteCommandResultExchangeStore? = nil,
        enrollmentStore: RemoteCommandEnrollmentStore? = nil,
        pollingInterval: Duration? = nil,
        socketEnabled: Bool = true,
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
        self.socketEnabled = socketEnabled
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
        startedAt = clock.now
        reconciliation = AccountSyncReconciliationSchedule(intervalOverride: pollingInterval)
        if socketEnabled {
            socket = AccountSyncSocket(
                open: { [weak self] in
                    guard let self,
                          isCurrentConnection(generation) else { throw CancellationError() }
                    return try await openAccountSocket(deviceID: deviceID, generation: generation)
                },
                onHint: { [weak self] in
                    guard let self, isCurrentConnection(generation) else { return }
                    reconciliation.invalidate(at: elapsed)
                    launchDueReconciliations(deviceID: deviceID, generation: generation)
                },
                onFailure: { [weak self] error, reason, token, status in
                    guard let self, isCurrentConnection(generation) else { return false }
                    let failure: Error = status.map { NativeAccountSyncError.rejected($0) } ?? error
                    return await handleSocketFailure(
                        failure,
                        reason: reason,
                        token: token,
                        generation: generation
                    )
                }
            )
            connectivityObserver = NativeAccountSyncConnectivityObserver { [weak self] in
                guard let self, isCurrentConnection(generation) else { return }
                socket?.reconnect()
                reconciliation.resume(at: elapsed)
                networkTick(deviceID: deviceID, generation: generation)
            }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.networkTick(deviceID: deviceID, generation: generation)
                else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    @discardableResult
    private func networkTick(deviceID: UUID, generation: Int) -> Duration? {
        guard isCurrentConnection(generation) else { return nil }
        socket?.tick()
        launchDueReconciliations(deviceID: deviceID, generation: generation)
        return min(pollingInterval ?? .seconds(1), .seconds(1))
    }

    func disconnect() {
        statusPublicationTask?.cancel()
        statusPublicationTask = nil
        statusPublications = AccountStatusPublicationLedger()
        stopNetworkActivity()
        onSynchronized = nil
        onOffline = nil
        onWakeStatus = nil
        onRemoteOverride = nil
        onRemoteCommandResult = nil
        onFailure = nil
        healthyChannels.removeAll()
        distributedPeerEpochs.removeAll()
        requiredChannels = [.accountState, .remoteOverride, .remoteCommands, .peerDevices]
        deviceStatusGeneration += 1
    }

    /// Cancels immediately, then joins owned operations before their dependencies
    /// are torn down. Normal interactive disconnect remains nonblocking.
    /// Call only from outside those operations. Socket tasks remain driver-owned.
    func disconnectAndWaitForPendingOperations() async {
        let pending = Array(reconciliationTasks.values) +
            [pollingTask, statusPublicationTask].compactMap(\.self)
        let refresh = tokenRefreshTask
        let publication = resultPublicationTask
        disconnect()
        for operation in pending {
            await operation.value
        }
        _ = try? await refresh?.value
        _ = try? await publication?.value
    }

    func stopNetworkActivity() {
        connectionGeneration += 1
        pollingTask?.cancel()
        pollingTask = nil
        socket?.stop()
        socket = nil
        connectivityObserver?.stop()
        connectivityObserver = nil
        for task in reconciliationTasks.values {
            task.cancel()
        }
        reconciliationTasks.removeAll()
        statusPublicationTask?.cancel()
        statusPublications.abortInFlight()
        deviceStatusGeneration += 1
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        tokenRefreshGeneration += 1
        resultPublicationTask?.cancel()
        resultPublicationTask = nil
        resultPublicationGeneration += 1
        publishedResults.removeAll()
    }

    private var elapsed: Duration {
        startedAt.duration(to: clock.now)
    }

    func handleSocketFailure(
        _ error: Error,
        reason: String?,
        token: String?,
        generation: Int
    ) async -> Bool {
        if ["device_revoked", "authorization_revoked", "account_recovery", "account_deleted"]
            .contains(reason ?? "") {
            recordOperationFailure(NativeAccountSyncError.rejected(403), channel: .accountState)
            return false
        }
        if reason == "authorization_expired" || (Self.isUnauthorized(error) && token != nil) {
            do {
                try await refreshAccessToken(rejectedAccessToken: token)
            } catch {
                guard isCurrentConnection(generation) else { return false }
                recordOperationFailure(error, channel: .accountState)
                return false
            }
        } else if Self.isTerminalSyncError(error) {
            recordOperationFailure(error, channel: .accountState)
            return false
        }
        return isCurrentConnection(generation)
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if case NativeAccountSyncError.rejected(401) = error {
            return true
        }
        return false
    }

    private static func isTerminalSyncError(_ error: Error) -> Bool {
        switch error {
        case NativeAccountSyncError.missingCredentials,
             AccountOAuthTokenRefreshError.missingCredentials,
             AccountOAuthTokenRefreshError.rejected,
             NativeAccountSyncError.rejected(401),
             NativeAccountSyncError.rejected(403): true
        default: false
        }
    }

    private func launchDueReconciliations(deviceID: UUID, generation: Int) {
        for channel in reconciliation.beginDue(at: elapsed) {
            reconciliationTasks[channel] = Task { [weak self] in
                guard let self else { return }
                let succeeded = await pollWithRefresh(
                    deviceID: deviceID,
                    channel: Self.healthChannel(channel),
                    generation: generation
                ) { [self] in
                    try await reconcile(channel, deviceID: deviceID, generation: generation)
                }
                guard isCurrentConnection(generation) else { return }
                reconciliation.finish(channel, at: elapsed, succeeded: succeeded)
                reconciliationTasks[channel] = nil
            }
        }
    }

    static func healthChannel(_ channel: AccountSyncReconciliationSchedule
        .Channel) -> AccountHealthChannel {
        switch channel {
        case .commands: .remoteCommands
        case .overrides: .remoteOverride
        case .wake: .accountState
        case .peers: .peerDevices
        case .results: .commandResults
        }
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        guard let attempt = statusPublications.begin(report) else { return }
        statusPublicationTask?.cancel()
        requiredChannels.insert(.deviceStatus)
        deviceStatusGeneration += 1
        let generation = deviceStatusGeneration
        let connection = connectionGeneration
        do {
            try enrollmentStore.recordEligibility(
                statusVersion: report.statusVersion,
                scheduleDigest: report.scheduleDigest
            )
        } catch {
            statusPublications.finish(attempt, succeeded: false)
            recordOperationFailure(
                NativeAccountSyncError.missingCredentials,
                channel: .deviceStatus
            )
            return
        }
        statusPublicationTask = Task { [weak self] in
            guard let self else { return }
            let succeeded = await pollWithRefresh(
                deviceID: deviceID, channel: .deviceStatus, generation: connection
            ) { [self] in
                let credentials = try currentCredentials(deviceID: deviceID)
                _ = try await authorizedHTTP.post(
                    path: "/sync/status",
                    body: report.encodedBody(),
                    deviceID: deviceID,
                    accessToken: credentials.accessToken,
                    signingPrivateKey: credentials.keys.signingPrivateKey
                )
            }
            guard generation == deviceStatusGeneration,
                  isCurrentConnection(connection) else { return }
            statusPublications.finish(attempt, succeeded: succeeded)
        }
    }
}
