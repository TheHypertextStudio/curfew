@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct AccountOAuthHandoffRouterTests {
    @MainActor
    @Test("An explicitly opened account handoff reaches only its pending OAuth request")
    func accountHandoffPreservesClaimedCallbackValidation() throws {
        let flavor = CurfewFlavor.current
        let redirectURI = AccountOAuthClaimedCallback.redirectURI(for: .current)
        let router = AccountOAuthCallbackRouter()
        let scheme = DocketOAuthAuthorizationRequest.callbackScheme(for: flavor)
        let handoff = try #require(URL(
            string: "\(scheme)://account-oauth/callback?code=code&state=expected-state"
        ))
        let docket = try #require(URL(
            string: "\(scheme)://docket-oauth/callback?code=code&state=expected-state"
        ))
        var received: URL?

        #expect(!router.route(handoff))
        _ = try router.register(
            expectedState: "expected-state",
            expectedRedirectURI: redirectURI
        ) { received = $0 }

        #expect(!router.route(docket))
        #expect(try !router.route(#require(URL(
            string: "\(scheme)://account-oauth/callback?code=code&state=wrong-state"
        ))))
        #expect(received == nil)
        #expect(router.route(handoff))
        #expect(received?.absoluteString == redirectURI + "?code=code&state=expected-state")
        #expect(!router.route(handoff))
    }
}
