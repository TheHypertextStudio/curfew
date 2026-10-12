import CurfewKit
import CurfewProtocols
import Foundation

@MainActor
extension NativeAccountSyncTransport {
    func openAccountSocket(
        deviceID: UUID,
        generation: Int
    ) async throws -> any AccountSyncSocketConnection {
        let credentials = try currentCredentials(deviceID: deviceID)
        do {
            return try await authorizedHTTP.openSocket(
                deviceID: deviceID,
                accessToken: credentials.accessToken,
                signingPrivateKey: credentials.keys.signingPrivateKey
            )
        } catch NativeAccountSyncError.rejected(401) {
            guard isCurrentConnection(generation) else { throw CancellationError() }
            try await refreshAccessToken(rejectedAccessToken: credentials.accessToken)
            guard isCurrentConnection(generation) else { throw CancellationError() }
            let refreshed = try currentCredentials(deviceID: deviceID)
            return try await authorizedHTTP.openSocket(
                deviceID: deviceID,
                accessToken: refreshed.accessToken,
                signingPrivateKey: refreshed.keys.signingPrivateKey
            )
        }
    }

    func pollOnce(deviceID: UUID) async {
        let generation = connectionGeneration
        for channel: AccountSyncReconciliationSchedule.Channel in [
            .overrides,
            .results,
            .peers,
            .wake,
            .commands
        ] {
            guard isCurrentConnection(generation) else { return }
            await pollWithRefresh(
                deviceID: deviceID,
                channel: Self.healthChannel(channel),
                generation: generation
            ) { [self] in
                try await reconcile(channel, deviceID: deviceID, generation: generation)
            }
        }
    }

    @discardableResult
    func pollWithRefresh(
        deviceID _: UUID,
        channel: AccountHealthChannel,
        generation: Int,
        operation: @MainActor () async throws -> Void
    ) async -> Bool {
        guard isCurrentConnection(generation) else { return false }
        let rejectedAccessToken = try? storedAccessToken()
        do {
            try await operation()
            guard isCurrentConnection(generation) else { return false }
            recordSuccessfulOperation(channel)
            return true
        } catch NativeAccountSyncError.rejected(401) {
            guard isCurrentConnection(generation) else { return false }
            do {
                try await refreshAccessToken(rejectedAccessToken: rejectedAccessToken)
                guard isCurrentConnection(generation) else { return false }
                try await operation()
                guard isCurrentConnection(generation) else { return false }
                recordSuccessfulOperation(channel)
                return true
            } catch {
                guard isCurrentConnection(generation) else { return false }
                recordPollFailure(error, channel: channel)
            }
        } catch {
            guard isCurrentConnection(generation) else { return false }
            recordPollFailure(error, channel: channel)
        }
        return false
    }

    func refreshAccessToken(rejectedAccessToken: String?) async throws {
        try Task.checkCancellation()
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
        tokenRefreshGeneration += 1
        let generation = tokenRefreshGeneration
        defer {
            if generation == tokenRefreshGeneration {
                tokenRefreshTask = nil
            }
        }
        try await task.value
    }

    private func storedAccessToken() throws -> String {
        guard let tokenData = try secretStore.data(for: "oauth-access-token"),
              let accessToken = String(data: tokenData, encoding: .utf8)
        else { throw NativeAccountSyncError.missingCredentials }
        return accessToken
    }

    func currentCredentials(
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

    func reconcile(
        _ channel: AccountSyncReconciliationSchedule.Channel,
        deviceID: UUID,
        generation: Int
    ) async throws {
        guard isCurrentConnection(generation) else { return }
        if channel == .results, try resultExchangeStore.pendingResults().isEmpty {
            return
        }
        if channel == .overrides {
            let remoteOverride = try await fetchRemoteOverride(deviceID: deviceID)
            guard isCurrentConnection(generation) else { return }
            onRemoteOverride?(remoteOverride)
            return
        }
        switch channel {
        case .results:
            try await reconcilePendingResults(deviceID: deviceID, generation: generation)
        case .peers:
            let credentials = try currentCredentials(deviceID: deviceID)
            try await distributeRootKey(
                deviceID: deviceID,
                accessToken: credentials.accessToken,
                keys: credentials.keys,
                generation: generation
            )
        case .commands:
            try await reconcilePendingResults(deviceID: deviceID, generation: generation)
            guard isCurrentConnection(generation) else { throw CancellationError() }
            try await reconcileStateRead(channel, deviceID: deviceID, generation: generation)
        case .wake:
            try await reconcileStateRead(channel, deviceID: deviceID, generation: generation)
        case .overrides: break
        }
    }

    private func reconcilePendingResults(deviceID: UUID, generation: Int) async throws {
        guard isCurrentConnection(generation) else { throw CancellationError() }
        if let resultPublicationTask {
            try await resultPublicationTask.value
            return
        }
        guard try !resultExchangeStore.pendingResults().isEmpty else { return }
        resultPublicationGeneration += 1
        let publication = resultPublicationGeneration
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                if publication == resultPublicationGeneration {
                    resultPublicationTask = nil
                }
            }
            guard isCurrentConnection(generation) else { throw CancellationError() }
            let credentials = try currentCredentials(deviceID: deviceID)
            try await publishPendingRemoteCommandResults(
                deviceID: deviceID, accessToken: credentials.accessToken,
                signingPrivateKey: credentials.keys.signingPrivateKey, generation: generation
            )
        }
        resultPublicationTask = task
        try await task.value
    }

    private func reconcileStateRead(
        _ channel: AccountSyncReconciliationSchedule.Channel,
        deviceID: UUID,
        generation: Int
    ) async throws {
        let credentials = try currentCredentials(deviceID: deviceID)
        let path = channel == .wake ? "/sync/wake/status" : "/sync/remote-control/commands"
        guard let data = try await authorizedHTTP.get(
            path: path,
            deviceID: deviceID,
            accessToken: credentials.accessToken,
            signingPrivateKey: credentials.keys.signingPrivateKey
        ), isCurrentConnection(generation) else { return }
        if channel == .wake {
            try onWakeStatus?(Self.wakeStatus(WakeStatus(data: data)))
        } else {
            for delivery in try Self
                .remoteCommandDeliveries(RemoteCommandDeliveryBatch(data: data)) {
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
        let pending = try resultExchangeStore.pendingResults()
        try publishedResults.removeAll {
            try !pending.contains($0.result) || resultExchangeStore.pendingReceipt(for: $0.result)
                != $0.receipt
        }
        for result in pending where !publishedResults.contains(where: { $0.result == result }) {
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
            let candidate = CoordinatorSignedRemoteCommandResultReceiptEnvelope(
                compactJWS: receipt.compactJws
            )
            try resultExchangeStore.recordReceipt(candidate, for: result)
            publishedResults.append((result, candidate))
        }
    }

    private func distributeRootKey(
        deviceID: UUID,
        accessToken: String,
        keys: AccountDeviceKeyMaterial,
        generation: Int
    ) async throws {
        guard let data = try await authorizedHTTP.get(
            path: "/sync/devices",
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: keys.signingPrivateKey
        ) else { return }
        guard isCurrentConnection(generation) else { return }
        let devices = try JSONDecoder().decode(
            [CurfewProtocols.AccountDeviceEnrollment].self,
            from: data
        )
        for peer in devices where peer.deviceID != deviceID.uuidString.lowercased() {
            guard isCurrentConnection(generation) else { return }
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
            guard isCurrentConnection(generation) else { return }
            distributedPeerEpochs.insert(fingerprint)
        }
    }
}
