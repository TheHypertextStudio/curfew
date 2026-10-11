import CryptoKit
import Foundation

public enum RemoteCommandResultReceiptVerificationError: Error, Equatable {
    case malformedJWS
    case invalidHeader
    case unknownKey
    case invalidKey
    case invalidSignature
    case invalidProof
    case expired
    case resultMismatch
}

/// Verifies the coordinator's proof of durable acceptance before the daemon
/// removes a terminal result from its outbox.
public struct RemoteCommandResultReceiptVerifier: Sendable {
    private let jwks: RemoteCommandJWKS

    public init(jwks: RemoteCommandJWKS) {
        self.jwks = jwks
    }

    public func verify(
        _ envelope: CoordinatorSignedRemoteCommandResultReceiptEnvelope,
        for result: RemoteCommandResult,
        at now: Date = Date()
    ) throws -> RemoteCommandResultIdentity {
        let segments = envelope.compactJWS.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = Base64URL.decode(String(segments[0])),
              let payloadData = Base64URL.decode(String(segments[1])),
              let signatureData = Base64URL.decode(String(segments[2])),
              signatureData.count == 64
        else {
            throw RemoteCommandResultReceiptVerificationError.malformedJWS
        }

        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: headerData)
        } catch {
            throw RemoteCommandResultReceiptVerificationError.invalidHeader
        }
        guard header.algorithm == "ES256",
              header.type == "curfew-result-receipt+jwt",
              !header.keyID.isEmpty,
              header.keyID.count <= 80
        else {
            throw RemoteCommandResultReceiptVerificationError.invalidHeader
        }
        let matchingKeys = jwks.keys.filter { $0.keyID == header.keyID }
        guard !matchingKeys.isEmpty else {
            throw RemoteCommandResultReceiptVerificationError.unknownKey
        }
        guard matchingKeys.count == 1,
              let publicKey = matchingKeys[0].signingPublicKey
        else {
            throw RemoteCommandResultReceiptVerificationError.invalidKey
        }
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        } catch {
            throw RemoteCommandResultReceiptVerificationError.invalidSignature
        }
        guard publicKey.isValidSignature(
            signature,
            for: Data("\(segments[0]).\(segments[1])".utf8)
        ) else {
            throw RemoteCommandResultReceiptVerificationError.invalidSignature
        }

        let proof: Proof
        do {
            proof = try JSONDecoder().decode(Proof.self, from: payloadData)
        } catch {
            throw RemoteCommandResultReceiptVerificationError.invalidProof
        }
        let expectedDigest = try Self.resultDigest(result)
        guard proof.coordinatorAudience == "curfew-device-agent",
              proof.sequence >= 1,
              proof.commandID.lowercased() == result.commandID.uuidString.lowercased(),
              proof.deviceID.lowercased() == result.deviceID.uuidString.lowercased(),
              proof.sequence == result.sequence,
              proof.resultDigest == expectedDigest,
              let acceptedAt = Self.date(proof.acceptedAt),
              let expiresAt = Self.date(proof.expiresAt),
              expiresAt > acceptedAt,
              expiresAt.timeIntervalSince(acceptedAt) <= 300,
              acceptedAt <= now.addingTimeInterval(60)
        else {
            throw RemoteCommandResultReceiptVerificationError.resultMismatch
        }
        guard expiresAt > now else {
            throw RemoteCommandResultReceiptVerificationError.expired
        }
        return RemoteCommandResultIdentity(result: result)
    }

    /// SHA-256 over the UTF-8 bytes of the RFC 8785 canonical projection used
    /// by protocol 0.0.9. This shape contains only strings and a safe integer,
    /// so Foundation's sorted-key encoding is byte-identical to JCS.
    public static func resultDigest(_ result: RemoteCommandResult) throws -> String {
        var object: [String: Any] = [
            "commandId": result.commandID.uuidString.lowercased(),
            "deviceId": result.deviceID.uuidString.lowercased(),
            "resolvedAt": wireDate(result.resolvedAt),
            "sequence": result.sequence,
            "stage": result.stage.rawValue
        ]
        if let deadline = result.appliedDeadline {
            object["appliedDeadline"] = wireDate(deadline)
        }
        if let rejection = result.rejectionCode {
            object["rejectionCode"] = rejection.rawValue
        }
        let canonical = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return Base64URL.encode(Data(SHA256.hash(data: canonical)))
    }

    private static func wireDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(_ value: String) -> Date? {
        guard value.range(
            of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$"#,
            options: .regularExpression
        ) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = value.contains(".")
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct Header: Decodable {
        let algorithm: String
        let keyID: String
        let type: String

        private enum CodingKeys: String, CodingKey {
            case algorithm = "alg"
            case keyID = "kid"
            case type = "typ"
        }
    }

    private struct Proof: Decodable {
        let acceptedAt: String
        let commandID: String
        let coordinatorAudience: String
        let deviceID: String
        let expiresAt: String
        let resultDigest: String
        let sequence: Int64

        private enum CodingKeys: String, CodingKey {
            case acceptedAt
            case commandID = "commandId"
            case coordinatorAudience
            case deviceID = "deviceId"
            case expiresAt
            case resultDigest
            case sequence
        }
    }
}
