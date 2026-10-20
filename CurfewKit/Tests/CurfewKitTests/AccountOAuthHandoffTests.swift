import CurfewKit
import Foundation
import Testing

struct AccountOAuthHandoffTests {
    @Test("Only the pending Curfew Dev callback becomes the claimed HTTPS callback")
    func studioDevCallbackRequiresExactStateAndRoute() throws {
        let expected = "https://curfew-account-staging.hypertext.studio/oauth/callback/native/macos"
        let incoming = try #require(URL(
            string: "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=short-code&state=pending-state"
        ))
        let canonical = AccountOAuthHandoff.canonicalCallback(
            from: incoming,
            registeredScheme: "studio.hypertext.curfew.studio.dev",
            expectedRedirectURI: expected,
            expectedState: "pending-state"
        )
        #expect(canonical?.absoluteString == expected + "?code=short-code&state=pending-state")

        #expect(AccountOAuthHandoff.canonicalCallback(
            from: incoming,
            registeredScheme: "studio.hypertext.curfew.studio.dev",
            expectedRedirectURI: expected,
            expectedState: "different-state"
        ) == nil)
    }

    @Test("A scheme hijack cannot impersonate a different route or weaken callback validation")
    func malformedOrUnrelatedCallbacksAreRejected() throws {
        let expected = "https://curfew-account-staging.hypertext.studio/oauth/callback/native/macos"
        for candidate in [
            "studio.hypertext.curfew://account-oauth/callback?code=c&state=s",
            "studio.hypertext.curfew.studio.dev://docket-oauth/callback?code=c&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth/other?code=c&state=s",
            "studio.hypertext.curfew.studio.dev://user@account-oauth/callback?code=c&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth:443/callback?code=c&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=c&state=s#fragment",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=c&state=s&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=c&code=d&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=&state=s",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=c&state=",
            "studio.hypertext.curfew.studio.dev://account-oauth/callback?code=c&state=s&error=denied"
        ] {
            let incoming = try #require(URL(string: candidate))
            #expect(AccountOAuthHandoff.canonicalCallback(
                from: incoming,
                registeredScheme: "studio.hypertext.curfew.studio.dev",
                expectedRedirectURI: expected,
                expectedState: "s"
            ) == nil)
        }
    }
}
