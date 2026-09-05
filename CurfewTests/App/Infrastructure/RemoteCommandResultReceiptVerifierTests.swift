import CryptoKit
@testable import Curfew
import Foundation
import Testing

struct RemoteCommandResultReceiptVerifierTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-05T12:01:00Z")!
    private let commandID = UUID(uuidString: "018f4f45-4d34-7d98-a6c5-4de1bd63a21c")!
    private let deviceID = UUID(uuidString: "018f4f45-7a98-7f53-89af-a4805f705d20")!

    @Test("Result digest matches the released 0.0.9 fractional timestamp vector")
    func matchesReleasedDigestVector() throws {
        let result = try vectorResult()

        #expect(
            try RemoteCommandResultReceiptVerifier.resultDigest(result)
                == "fklqwyZFhC9HaRAqnZyalSkC3UQLKW9nOMuNyCgttOY"
        )
    }

    @Test("Accepts only a coordinator signature bound to the exact pending result")
    func verifiesExactSignedReceipt() throws {
        let key = P256.Signing.PrivateKey()
        let result = try vectorResult()
        let receipt = try signedReceipt(
            result: result,
            digest: RemoteCommandResultReceiptVerifier.resultDigest(result),
            key: key
        )
        let verifier = RemoteCommandResultReceiptVerifier(
            jwks: RemoteCommandJWKS(keys: [
                RemoteCommandJWK(keyID: "result-receipt-key", publicKey: key.publicKey)
            ])
        )

        #expect(
            try verifier.verify(receipt, for: result, at: now)
                == RemoteCommandResultIdentity(result: result)
        )
    }

    @Test("A signed receipt for a different result cannot clear the daemon outbox")
    func rejectsDifferentResultDigest() throws {
        let key = P256.Signing.PrivateKey()
        let result = try vectorResult()
        let receipt = try signedReceipt(
            result: result,
            digest: String(repeating: "D", count: 43),
            key: key
        )
        let verifier = RemoteCommandResultReceiptVerifier(
            jwks: RemoteCommandJWKS(keys: [
                RemoteCommandJWK(keyID: "result-receipt-key", publicKey: key.publicKey)
            ])
        )

        #expect(throws: RemoteCommandResultReceiptVerificationError.resultMismatch) {
            try verifier.verify(receipt, for: result, at: now)
        }
    }

    private func vectorResult() throws -> RemoteCommandResult {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try RemoteCommandResult(
            commandID: commandID,
            deviceID: deviceID,
            sequence: 42,
            stage: .applied,
            resolvedAt: #require(formatter.date(from: "2026-09-05T12:00:00.123Z")),
            appliedDeadline: #require(
                formatter.date(from: "2026-09-05T12:30:00.456Z")
            )
        )
    }

    private func signedReceipt(
        result: RemoteCommandResult,
        digest: String,
        key: P256.Signing.PrivateKey
    ) throws -> CoordinatorSignedRemoteCommandResultReceiptEnvelope {
        let header = try JSONSerialization.data(
            withJSONObject: [
                "alg": "ES256",
                "kid": "result-receipt-key",
                "typ": "curfew-result-receipt+jwt"
            ],
            options: [.sortedKeys]
        )
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "acceptedAt": "2026-09-05T12:00:30.000Z",
                "commandId": result.commandID.uuidString.lowercased(),
                "coordinatorAudience": "curfew-device-agent",
                "deviceId": result.deviceID.uuidString.lowercased(),
                "expiresAt": "2026-09-05T12:05:30.000Z",
                "resultDigest": digest,
                "sequence": result.sequence
            ],
            options: [.sortedKeys]
        )
        let signingInput = "\(base64URL(header)).\(base64URL(payload))"
        let signature = try key.signature(for: Data(signingInput.utf8)).rawRepresentation
        return CoordinatorSignedRemoteCommandResultReceiptEnvelope(
            compactJWS: "\(signingInput).\(base64URL(signature))"
        )
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
