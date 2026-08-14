@testable import Curfew
import CryptoKit
import CurfewProtocols
import Foundation
import XCTest

@MainActor
final class NativeAccountSyncTransportTests: XCTestCase {
    func testDeviceProofBindsTokenMethodURLNonceAndBody() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let identifier = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")!
        let body = Data(#"{"deviceId":"018f4f45-cafe-7f00-9a82-e47805fb4d35"}"#.utf8)
        let proof = try AccountDeviceProofFactory(
            now: { now },
            identifier: { identifier }
        ).make(
            accessToken: "resource-bound-access-token",
            nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            method: "POST",
            url: URL(string: "https://curfew-sync.hypertext.studio/sync/devices/enroll")!,
            body: body,
            signingPrivateKey: key.rawRepresentation
        )

        let parts = proof.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        let header = try XCTUnwrap(decode(String(parts[0])))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: header) as? [String: String],
            ["alg": "ES256", "typ": "curfew-device-proof+jws"]
        )
        let claims = try DeviceProofClaims(data: XCTUnwrap(decode(String(parts[1]))))
        XCTAssertEqual(claims.httpMethod, "POST")
        XCTAssertEqual(claims.canonicalURL, "https://curfew-sync.hypertext.studio/sync/devices/enroll")
        XCTAssertEqual(claims.jti, identifier.uuidString.lowercased())
        XCTAssertEqual(claims.nonce, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertNotNil(claims.accessTokenHash)
        XCTAssertNotNil(claims.bodyDigest)

        let signature = try P256.Signing.ECDSASignature(
            rawRepresentation: XCTUnwrap(decode(String(parts[2])))
        )
        XCTAssertTrue(key.publicKey.isValidSignature(
            signature,
            for: Data("\(parts[0]).\(parts[1])".utf8)
        ))
    }

    private func decode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
