import CryptoKit
import CurfewProtocols
import Foundation

enum NativeAccountSyncError: Error {
    case missingCredentials
    case invalidResponse
    case rejected(Int)
}

private struct NativeAuthorizedWrite {
    let method: String
    let path: String
    let body: Data
    let deviceID: UUID
    let accessToken: String
    let signingPrivateKey: Data
}

final nonisolated class RejectingRedirectSessionDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
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
    private struct Challenge: Decodable { let nonce: String }
    private let baseURL = URL(string: "https://curfew-sync.hypertext.studio")!
    private let secretStore: any AccountSecretStoring
    private let keyStore: AccountDeviceKeyStore
    private let session: URLSession
    private let proofFactory: AccountDeviceProofFactory
    private var pollingTask: Task<Void, Never>?
    private var onWakeStatus: ((AccountWakeStatusUpdate) -> Void)?
    private var onRemoteOverride: ((AccountRemoteOverride) -> Void)?
    private var onFailure: ((String) -> Void)?
    private var distributedPeerEpochs: Set<String> = []

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        proofFactory: AccountDeviceProofFactory? = nil
    ) {
        self.secretStore = secretStore
        self.keyStore = AccountDeviceKeyStore(secretStore: secretStore)
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
        self.proofFactory = proofFactory ?? AccountDeviceProofFactory()
    }

    func connect(
        deviceID: UUID,
        onWakeStatus: @escaping (AccountWakeStatusUpdate) -> Void,
        onRemoteOverride: @escaping (AccountRemoteOverride) -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        disconnect()
        self.onWakeStatus = onWakeStatus
        self.onRemoteOverride = onRemoteOverride
        self.onFailure = onFailure
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(deviceID: deviceID)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func publishDeviceStatus(_ report: DeviceStatusReport, deviceID: UUID) {
        Task { [weak self] in
            do {
                guard let self,
                      let tokenData = try secretStore.data(for: "oauth-access-token"),
                      let accessToken = String(data: tokenData, encoding: .utf8),
                      let keys = try keyStore.load(deviceID: deviceID)
                else { throw NativeAccountSyncError.missingCredentials }
                try await authorizedPOST(
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

    private func poll(deviceID: UUID) async {
        do {
            guard let tokenData = try secretStore.data(for: "oauth-access-token"),
                  let accessToken = String(data: tokenData, encoding: .utf8),
                  let keys = try keyStore.load(deviceID: deviceID)
            else { throw NativeAccountSyncError.missingCredentials }

            do {
                try await distributeRootKey(
                    deviceID: deviceID,
                    accessToken: accessToken,
                    keys: keys
                )
            } catch {
                onFailure?("Encrypted device-key distribution is offline or rejected.")
            }

            if let data = try await authorizedGET(
                path: "/sync/wake/status",
                deviceID: deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            ) {
                try onWakeStatus?(Self.wakeStatus(WakeStatus(data: data)))
            }
            if let data = try await authorizedGET(
                path: "/sync/remote-overrides/active",
                deviceID: deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            ) {
                try onRemoteOverride?(Self.remoteOverride(RemoteOverride(data: data)))
            }
        } catch {
            onFailure?("Account sync is offline or rejected.")
        }
    }

    private func distributeRootKey(
        deviceID: UUID,
        accessToken: String,
        keys: AccountDeviceKeyMaterial
    ) async throws {
        guard let data = try await authorizedGET(
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
            try await authorizedPUT(
                path: "/sync/devices/\(peer.deviceID)/root-key-envelope",
                body: envelope.jsonData(),
                deviceID: deviceID,
                accessToken: accessToken,
                signingPrivateKey: keys.signingPrivateKey
            )
            distributedPeerEpochs.insert(fingerprint)
        }
    }

    private func authorizedGET(
        path: String,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Data? {
        let nonce = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let url = baseURL.appending(path: path)
        let proof = try proofFactory.make(.init(
            accessToken: accessToken,
            nonce: nonce,
            method: "GET",
            url: url,
            body: nil,
            signingPrivateKey: signingPrivateKey
        ))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(deviceID.uuidString.lowercased(), forHTTPHeaderField: "X-Curfew-Device-ID")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAccountSyncError.invalidResponse
        }
        if http.statusCode == 404 {
            return nil
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NativeAccountSyncError.rejected(http.statusCode)
        }
        return data
    }

    private func authorizedPUT(
        path: String,
        body: Data,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws {
        try await authorizedWrite(.init(
            method: "PUT",
            path: path,
            body: body,
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: signingPrivateKey
        ))
    }

    private func authorizedPOST(
        path: String,
        body: Data,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws {
        try await authorizedWrite(.init(
            method: "POST",
            path: path,
            body: body,
            deviceID: deviceID,
            accessToken: accessToken,
            signingPrivateKey: signingPrivateKey
        ))
    }

    private func authorizedWrite(_ input: NativeAuthorizedWrite) async throws {
        let nonce = try await challenge(deviceID: input.deviceID, accessToken: input.accessToken)
        let url = baseURL.appending(path: input.path)
        let proof = try proofFactory.make(.init(
            accessToken: input.accessToken,
            nonce: nonce,
            method: input.method,
            url: url,
            body: input.body,
            signingPrivateKey: input.signingPrivateKey
        ))
        var request = URLRequest(url: url)
        request.httpMethod = input.method
        request.httpBody = input.body
        request.setValue("Bearer \(input.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proof, forHTTPHeaderField: "DPoP")
        request.setValue(
            input.deviceID.uuidString.lowercased(),
            forHTTPHeaderField: "X-Curfew-Device-ID"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAccountSyncError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NativeAccountSyncError.rejected(http.statusCode)
        }
    }

    private func challenge(deviceID: UUID, accessToken: String) async throws -> String {
        let url = baseURL.appending(path: "/sync/device-proof/challenge")
        let body = try JSONSerialization.data(
            withJSONObject: ["deviceId": deviceID.uuidString.lowercased()],
            options: [.sortedKeys]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let nonce = try? JSONDecoder().decode(Challenge.self, from: data).nonce
        else { throw NativeAccountSyncError.invalidResponse }
        return nonce
    }
}
