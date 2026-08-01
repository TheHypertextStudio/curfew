@testable import Curfew
import Foundation
import Testing

/// Compatibility boundary for the internal app-to-license-issuer envelope.
/// This is intentionally local to Curfew: it is not an MCP or Sync protocol.
struct LicenseEnvelopeContractTests {
    @Test("The app embeds the provisioned Curfew Plus signing public key")
    func embedsProvisionedPublicKey() {
        #expect(
            LicenseGate.configuredPublicKeyBase64 ==
                "V54mfManht5dg5yhqX3iok9PkX9WLOpmyuF8rm2nG+o="
        )
    }

    @Test("subscription envelopes decode as Curfew Plus and retain refresh metadata")
    func decodesCurfewPlusSubscriptionEnvelope() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = Data("""
        {"email":"buyer@example.com","product":"curfew-plus","plan":"subscription",\
        "order_id":"sub_123","issued_at":"2026-07-31T00:00:00Z",\
        "expires_at":"2026-08-31T00:00:00Z","refresh_token":"refresh_123"}
        """.utf8)

        let license = try decoder.decode(LicenseKey.self, from: json)

        #expect(license.product == "curfew-plus")
        #expect(license.plan == .subscription)
        #expect(license.expiresAt != nil)
        #expect(license.refreshToken == "refresh_123")
    }
}
