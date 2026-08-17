import CryptoKit
import CurfewProtocols
import Foundation

enum NativeAccountSyncError: Error {
    case missingCredentials
    case invalidResponse
    case rejected(Int)
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
    let now: () -> Date
    let identifier: () -> UUID

    init(
        now: @escaping () -> Date = Date.init,
        identifier: @escaping () -> UUID = UUID.init
    ) {
        self.now = now
        self.identifier = identifier
    }

    func make(
        accessToken: String,
        nonce: String,
        method: String,
        url: URL,
        body: Data?,
        signingPrivateKey: Data
    ) throws -> String {
        let bodyDigest = try body.map { data -> String in
            let value = try JSONSerialization.jsonObject(with: data)
            let canonical = try JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            return Self.base64URL(Data(SHA256.hash(data: canonical)))
        }
        let claims = DeviceProofClaims(
            accessTokenHash: Self.base64URL(Data(SHA256.hash(data: Data(accessToken.utf8)))),
            bodyDigest: bodyDigest,
            canonicalURL: url.absoluteString,
            httpMethod: method,
            issuedAt: Self.dateFormatter.string(from: now()),
            jti: identifier().uuidString.lowercased(),
            nonce: nonce
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let header = Self.base64URL(Data(#"{"alg":"ES256","typ":"curfew-device-proof+jws"}"#.utf8))
        let payload = try Self.base64URL(encoder.encode(claims))
        let signingInput = "\(header).\(payload)"
        let key = try P256.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
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

    private func poll(deviceID: UUID) async {
        do {
            guard let tokenData = try secretStore.data(for: "oauth-access-token"),
                  let accessToken = String(data: tokenData, encoding: .utf8),
                  let keys = try keyStore.load(deviceID: deviceID)
            else { throw NativeAccountSyncError.missingCredentials }

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

    private func authorizedGET(
        path: String,
        deviceID: UUID,
        accessToken: String,
        signingPrivateKey: Data
    ) async throws -> Data? {
        let nonce = try await challenge(deviceID: deviceID, accessToken: accessToken)
        let url = baseURL.appending(path: path)
        let proof = try proofFactory.make(
            accessToken: accessToken,
            nonce: nonce,
            method: "GET",
            url: url,
            body: nil,
            signingPrivateKey: signingPrivateKey
        )
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

    private static func wakeStatus(_ value: WakeStatus) throws -> AccountWakeStatusUpdate {
        guard let campaignID = UUID(uuidString: value.campaignID),
              let deadline = date(value.finalDeadlineAt),
              let updatedAt = date(value.updatedAt)
        else { throw NativeAccountSyncError.invalidResponse }
        let selected = try value.selectedDeviceIDS.map { identifier in
            guard let value = UUID(uuidString: identifier) else {
                throw NativeAccountSyncError.invalidResponse
            }
            return value
        }
        let state: AccountWakeCampaignState = switch value.state {
        case .scheduled: .scheduled
        case .ringingAttempt: .ringingAttempt
        case .quietInterval: .quietInterval
        case .satisfied: .satisfied
        case .exhausted: .exhausted
        case .overridden: .overridden
        }
        return AccountWakeStatusUpdate(
            campaignID: campaignID,
            state: state,
            attemptNumber: value.attemptNumber,
            maximumAttempts: value.maximumAttempts,
            selectedDeviceIDs: selected,
            finalDeadlineAt: deadline,
            statusVersion: value.statusVersion,
            updatedAt: updatedAt
        )
    }

    private static func remoteOverride(_ value: RemoteOverride) throws -> AccountRemoteOverride {
        guard let overrideID = UUID(uuidString: value.overrideID),
              let requestID = UUID(uuidString: value.requestID),
              let startsAt = date(value.startsAt)
        else { throw NativeAccountSyncError.invalidResponse }
        let targets = try value.targetDeviceIDS.map { identifier in
            guard let value = UUID(uuidString: identifier) else {
                throw NativeAccountSyncError.invalidResponse
            }
            return value
        }
        let authorization: AccountRemoteOverride.AuthorizedBy = switch value.authorizedBy {
        case .freshWebAal2: .freshWebAAL2
        case .mcpUserApproval: .mcpUserApproval
        case .mcpPreauthorizedClient: .mcpPreauthorizedClient
        }
        let status: AccountRemoteOverride.Status = switch value.status {
        case .active: .active
        case .cancelled: .cancelled
        case .expired: .expired
        }
        return try AccountRemoteOverride(
            overrideID: overrideID,
            requestID: requestID,
            targetDeviceIDs: targets,
            reason: value.reason,
            durationMinutes: value.durationMinutes,
            startsAt: startsAt,
            authorizedBy: authorization,
            status: status
        )
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
