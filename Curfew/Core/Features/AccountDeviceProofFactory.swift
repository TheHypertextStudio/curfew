import CryptoKit
import CurfewProtocols
import Foundation

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
