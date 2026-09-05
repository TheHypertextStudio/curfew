import CryptoKit
@testable import Curfew
import Foundation
import Testing

final class RemoteJWKSURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, data) = try handler(request)
            let requestURL = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: requestURL,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct RemoteCommandVerifierFixture {
    let verifier: RemoteCommandVerifier
    let envelope: Data
    let commandID: UUID
}

struct StaticRemoteCommandJWKSProvider: RemoteCommandJWKSProvider {
    let keys: [RemoteCommandJWK]

    func jwks() throws -> RemoteCommandJWKS {
        RemoteCommandJWKS(keys: keys)
    }
}

enum RemoteCommandJWSTestSupport {
    static func sign(
        payload: RemoteLockoutCommandPayload,
        privateKey: P256.Signing.PrivateKey,
        keyID: String
    ) throws -> String {
        let header = try JSONSerialization.data(
            withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "curfew-command+jwt"],
            options: [.sortedKeys]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(payload)
        let signingInput = "\(base64URL(header)).\(base64URL(body))"
        let signature = try privateKey.signature(for: Data(signingInput.utf8)).rawRepresentation
        return "\(signingInput).\(base64URL(signature))"
    }

    static func tamper(_ compactJWS: String) -> String {
        let parts = compactJWS.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return compactJWS }
        let replacement = parts[2].first == "A" ? "B" : "A"
        return "\(parts[0]).\(parts[1]).\(replacement)\(parts[2].dropFirst())"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
