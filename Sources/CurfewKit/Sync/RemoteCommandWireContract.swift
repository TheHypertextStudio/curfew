import CryptoKit
import Foundation

/// A post-verification command. Only this value may cross the enforcement boundary.
public struct AuthenticatedRemoteCommand: Equatable, Sendable {
    public let lockoutID: UUID
    public let idempotencyKey: String
    public let userID: String
    public let deviceID: UUID
    public let sequence: Int64
    public let scheduledUnlockAt: Date
    public let issuedAt: Date
    public let expiresAt: Date
    public let nonce: String
    public let statusVersion: Int
    public let scheduleDigest: String
}

public enum RemoteLockoutDeadlinePolicy: Codable, Equatable, Sendable {
    case fixedDuration(seconds: Int)
    case nextScheduledUnlock

    private enum CodingKeys: String, CodingKey {
        case kind
        case durationSeconds
    }

    private enum Kind: String, Codable {
        case fixedDuration = "fixed_duration"
        case nextScheduledUnlock = "next_scheduled_unlock"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .fixedDuration:
            self = try .fixedDuration(
                seconds: container.decode(Int.self, forKey: .durationSeconds)
            )
        case .nextScheduledUnlock:
            guard !container.contains(.durationSeconds) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .durationSeconds,
                    in: container,
                    debugDescription: "next_scheduled_unlock cannot carry durationSeconds"
                )
            }
            self = .nextScheduledUnlock
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixedDuration(let seconds):
            try container.encode(Kind.fixedDuration, forKey: .kind)
            try container.encode(seconds, forKey: .durationSeconds)
        case .nextScheduledUnlock:
            try container.encode(Kind.nextScheduledUnlock, forKey: .kind)
        }
    }
}

/// Exact claims carried by the signed `RemoteLockCommand` protocol shape.
public struct RemoteLockoutCommandPayload: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let idempotencyKey: String
    public let userID: String
    public let deviceID: UUID
    public let sequence: Int64
    public let kind: String
    public let deadlinePolicy: RemoteLockoutDeadlinePolicy
    public let issuedAt: Date
    public let expiresAt: Date
    public let nonce: String
    public let coordinatorAudience: String
    public let statusVersion: Int
    public let scheduleDigest: String

    public init(
        commandID: UUID,
        idempotencyKey: String,
        userID: String,
        deviceID: UUID,
        sequence: Int64,
        deadlinePolicy: RemoteLockoutDeadlinePolicy,
        issuedAt: Date,
        expiresAt: Date,
        nonce: String,
        coordinatorAudience: String,
        statusVersion: Int,
        scheduleDigest: String,
        kind: String = "remote_lock"
    ) {
        self.commandID = commandID
        self.idempotencyKey = idempotencyKey
        self.userID = userID
        self.deviceID = deviceID
        self.sequence = sequence
        self.kind = kind
        self.deadlinePolicy = deadlinePolicy
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.coordinatorAudience = coordinatorAudience
        self.statusVersion = statusVersion
        self.scheduleDigest = scheduleDigest
    }

    private enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case idempotencyKey
        case userID = "userId"
        case deviceID = "deviceId"
        case sequence
        case kind
        case deadlinePolicy
        case issuedAt
        case expiresAt
        case nonce
        case coordinatorAudience
        case statusVersion
        case scheduleDigest
    }
}

public struct RemoteCommandJWK: Codable, Equatable, Sendable {
    public let keyType: String
    public let curve: String
    public let algorithm: String
    public let use: String
    public let keyID: String
    public let x: String
    public let y: String

    public init(
        keyType: String = "EC",
        curve: String = "P-256",
        algorithm: String = "ES256",
        use: String = "sig",
        keyID: String,
        x: String,
        y: String
    ) {
        self.keyType = keyType
        self.curve = curve
        self.algorithm = algorithm
        self.use = use
        self.keyID = keyID
        self.x = x
        self.y = y
    }

    public init(keyID: String, publicKey: P256.Signing.PublicKey) {
        let representation = publicKey.x963Representation
        self.init(
            keyID: keyID,
            x: Base64URL.encode(representation[1 ..< 33]),
            y: Base64URL.encode(representation[33 ..< 65])
        )
    }

    public var signingPublicKey: P256.Signing.PublicKey? {
        guard keyType == "EC", curve == "P-256", algorithm == "ES256", use == "sig",
              let xData = Base64URL.decode(x), xData.count == 32,
              let yData = Base64URL.decode(y), yData.count == 32
        else { return nil }
        return try? P256.Signing.PublicKey(
            x963Representation: Data([0x04]) + xData + yData
        )
    }

    private enum CodingKeys: String, CodingKey {
        case keyType = "kty"
        case curve = "crv"
        case algorithm = "alg"
        case use
        case keyID = "kid"
        case x
        case y
    }
}

public struct RemoteCommandJWKS: Codable, Equatable, Sendable {
    public let keys: [RemoteCommandJWK]

    public init(keys: [RemoteCommandJWK]) {
        self.keys = keys
    }
}

public protocol RemoteCommandJWKSProvider: Sendable {
    func jwks() throws -> RemoteCommandJWKS
}
