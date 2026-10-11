import CryptoKit
import Foundation

public struct RemoteCommandVerifierConfiguration: Equatable, Sendable {
    public let userID: String
    public let deviceID: UUID
    public let coordinatorAudience: String

    public init(
        userID: String,
        deviceID: UUID,
        coordinatorAudience: String = "curfew-device-agent"
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.coordinatorAudience = coordinatorAudience
    }
}

public enum RemoteCommandVerificationError: Error, Equatable {
    case malformedEnvelope
    case malformedJWS
    case invalidHeader
    case unknownKey
    case invalidKey
    case invalidSignature
    case invalidCommand
    case invalidAudience
    case nonTargetDevice
    case expired
    case invalidClock
    case unresolvedDeadline
}

public struct RemoteCommandVerifier: Sendable {
    private let configuration: RemoteCommandVerifierConfiguration
    private let jwks: RemoteCommandJWKS
    private let nextScheduledUnlock: @Sendable (Date) -> Date?

    public init(
        configuration: RemoteCommandVerifierConfiguration,
        jwksProvider: any RemoteCommandJWKSProvider,
        nextScheduledUnlock: @escaping @Sendable (Date) -> Date? = { _ in nil }
    ) throws {
        guard !configuration.userID.isEmpty, configuration.userID.count <= 128 else {
            throw RemoteCommandVerificationError.invalidCommand
        }
        self.configuration = configuration
        self.jwks = try jwksProvider.jwks()
        self.nextScheduledUnlock = nextScheduledUnlock
    }

    public func verifiedLockoutRecord(
        envelope data: Data,
        at now: Date = Date()
    ) throws -> AuthenticatedRemoteCommand {
        let envelope: SignedRemoteLockoutCommandEnvelope
        do {
            envelope = try JSONDecoder().decode(SignedRemoteLockoutCommandEnvelope.self, from: data)
        } catch {
            throw RemoteCommandVerificationError.malformedEnvelope
        }

        let segments = envelope.compactJWS.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = Base64URL.decode(String(segments[0])),
              let payloadData = Base64URL.decode(String(segments[1])),
              let signatureData = Base64URL.decode(String(segments[2])),
              signatureData.count == 64
        else {
            throw RemoteCommandVerificationError.malformedJWS
        }

        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: headerData)
        } catch {
            throw RemoteCommandVerificationError.invalidHeader
        }
        guard header.algorithm == "ES256", header.type == "curfew-command+jwt",
              !header.keyID.isEmpty, header.keyID.count <= 80
        else {
            throw RemoteCommandVerificationError.invalidHeader
        }

        let matchingKeys = jwks.keys.filter { $0.keyID == header.keyID }
        guard !matchingKeys.isEmpty else {
            throw RemoteCommandVerificationError.unknownKey
        }
        guard matchingKeys.count == 1, let publicKey = matchingKeys[0].signingPublicKey else {
            throw RemoteCommandVerificationError.invalidKey
        }

        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        } catch {
            throw RemoteCommandVerificationError.invalidSignature
        }
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        guard publicKey.isValidSignature(signature, for: signingInput) else {
            throw RemoteCommandVerificationError.invalidSignature
        }

        let payload: RemoteLockoutCommandPayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(RemoteLockoutCommandPayload.self, from: payloadData)
        } catch {
            throw RemoteCommandVerificationError.invalidCommand
        }
        try validate(payload, at: now)

        let scheduledUnlockAt: Date
        switch payload.deadlinePolicy {
        case .fixedDuration(let seconds):
            guard (300 ... 43200).contains(seconds) else {
                throw RemoteCommandVerificationError.invalidCommand
            }
            scheduledUnlockAt = now.addingTimeInterval(TimeInterval(seconds))
        case .nextScheduledUnlock:
            guard let resolved = nextScheduledUnlock(now), resolved > now else {
                throw RemoteCommandVerificationError.unresolvedDeadline
            }
            scheduledUnlockAt = resolved
        }

        return AuthenticatedRemoteCommand(
            lockoutID: payload.commandID,
            idempotencyKey: payload.idempotencyKey,
            userID: payload.userID,
            deviceID: payload.deviceID,
            sequence: payload.sequence,
            scheduledUnlockAt: scheduledUnlockAt,
            issuedAt: payload.issuedAt,
            expiresAt: payload.expiresAt,
            nonce: payload.nonce,
            statusVersion: payload.statusVersion,
            scheduleDigest: payload.scheduleDigest
        )
    }

    private func validate(_ payload: RemoteLockoutCommandPayload, at now: Date) throws {
        guard payload.kind == "lock_device",
              payload.userID == configuration.userID,
              !payload.userID.isEmpty,
              payload.userID.count <= 128,
              payload.sequence >= 1,
              payload.statusVersion >= 0,
              Self.matchesEntropy(payload.idempotencyKey),
              Self.matchesEntropy(payload.nonce),
              Self.matchesSHA256(payload.scheduleDigest)
        else {
            throw RemoteCommandVerificationError.invalidCommand
        }
        guard payload.coordinatorAudience == configuration.coordinatorAudience else {
            throw RemoteCommandVerificationError.invalidAudience
        }
        guard payload.deviceID == configuration.deviceID else {
            throw RemoteCommandVerificationError.nonTargetDevice
        }
        guard payload.expiresAt > now else {
            throw RemoteCommandVerificationError.expired
        }
        guard payload.expiresAt > payload.issuedAt,
              payload.expiresAt.timeIntervalSince(payload.issuedAt) <= 300,
              payload.issuedAt <= now.addingTimeInterval(60)
        else {
            throw RemoteCommandVerificationError.invalidClock
        }
    }

    private static func matchesEntropy(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{22,86}$", options: .regularExpression) != nil
    }

    private static func matchesSHA256(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    }

    private struct Header: Codable {
        let algorithm: String
        let keyID: String
        let type: String

        private enum CodingKeys: String, CodingKey {
            case algorithm = "alg"
            case keyID = "kid"
            case type = "typ"
        }
    }
}
