@testable import Curfew
import CurfewProtocols
import Foundation
import Testing

struct AccountOAuthEnrollmentTests {
    @Test("Native OAuth uses PKCE, the sync resource, and every first-party scope")
    func authorizationRequestIsResourceBound() throws {
        let request = try AccountOAuthEnrollmentRequest.create(
            clientID: "curfew-macos-test",
            callbackScheme: "studio.hypertext.curfew",
            state: "state-value",
            verifier: String(repeating: "v", count: 64)
        )
        let components = try #require(URLComponents(
            url: request.authorizationURL,
            resolvingAgainstBaseURL: false
        ))
        let query = try Dictionary(uniqueKeysWithValues: #require(components.queryItems).map {
            try ($0.name, #require($0.value))
        })

        #expect(components.scheme == "https")
        #expect(components.host == "curfew-account.hypertext.studio")
        #expect(query["resource"] == "https://curfew-sync.hypertext.studio")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "state-value")
        #expect(query["redirect_uri"] == "studio.hypertext.curfew://oauth/callback")
        let scopes = try Set(#require(query["scope"]).split(separator: " ").map(String.init))
        #expect(scopes.contains("openid"))
        #expect(scopes.contains("offline_access"))
        let required = Set([
            CurfewFirstPartyOAuthScope.curfewAccountRead,
            .curfewDevicesRead,
            .curfewDevicesWrite,
            .curfewEntitlementsRead,
            .curfewSyncRead,
            .curfewSyncWrite,
            .curfewWakeRead,
            .curfewWakeWrite
        ].map(\.rawValue))
        #expect(scopes.isSuperset(of: required))
    }

    @Test("Native OAuth rejects a callback scheme outside Curfew's package namespace")
    func callbackSchemeIsPinned() {
        #expect(throws: AccountOAuthEnrollmentError.self) {
            _ = try AccountOAuthEnrollmentRequest.create(
                clientID: "curfew-macos-test",
                callbackScheme: "curfew",
                state: "state-value",
                verifier: String(repeating: "v", count: 64)
            )
        }
    }

    @Test("OAuth callback returns a code only for the exact one-time state")
    func callbackStateIsExact() throws {
        let callback =
            try #require(
                URL(
                    string: "studio.hypertext.curfew://oauth/callback?code=code-value&state=state-value"
                )
            )

        #expect(try AccountOAuthCallback.authorizationCode(
            from: callback,
            expectedState: "state-value"
        ) == "code-value")
        #expect(throws: AccountOAuthEnrollmentError.self) {
            _ = try AccountOAuthCallback.authorizationCode(
                from: callback,
                expectedState: "different-state"
            )
        }
    }

    @Test("OAuth callback surfaces provider rejection without accepting a code")
    func callbackProviderErrorFailsClosed() throws {
        let callback =
            try #require(
                URL(
                    string: "studio.hypertext.curfew://oauth/callback?error=access_denied&state=state-value"
                )
            )

        #expect(throws: AccountOAuthEnrollmentError.self) {
            _ = try AccountOAuthCallback.authorizationCode(
                from: callback,
                expectedState: "state-value"
            )
        }
    }

    @Test("OAuth wire responses require a public client id and rotating refresh token")
    func tokenAndRegistrationResponsesFailClosed() throws {
        let registration = try AccountOAuthWire.registration(
            from: Data(#"{"client_id":"curfew-native-client"}"#.utf8)
        )
        let tokens = try AccountOAuthWire.tokens(
            from: Data(#"{"access_token":"access","refresh_token":"refresh","token_type":"Bearer"}"#
                .utf8)
        )

        #expect(registration.clientID == "curfew-native-client")
        #expect(tokens.accessToken == "access")
        #expect(tokens.refreshToken == "refresh")
        #expect(throws: AccountOAuthEnrollmentError.self) {
            _ = try AccountOAuthWire.tokens(
                from: Data(#"{"access_token":"access","token_type":"Bearer"}"#.utf8)
            )
        }
    }
}
