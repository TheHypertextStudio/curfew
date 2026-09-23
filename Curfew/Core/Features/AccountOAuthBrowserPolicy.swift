import AuthenticationServices
import Foundation

enum AccountOAuthBrowserPolicy {
    static func configure(_ session: ASWebAuthenticationSession) {
        // Account enrollment is passkey-first. Preserve the normal browser
        // session so the user's existing account and credential provider are
        // available to the authorization flow.
        session.prefersEphemeralWebBrowserSession = false
    }
}

enum AccountOAuthCallbackPolicy {
    static func callback(for endpoints: CurfewServiceEndpoints) -> ASWebAuthenticationSession
        .Callback {
        guard let host = endpoints.accountOrigin.host else {
            preconditionFailure("Curfew account origin must have an HTTPS host")
        }
        return .https(host: host, path: AccountOAuthClaimedCallback.path)
    }

    static func accepts(_ url: URL, for endpoints: CurfewServiceEndpoints) -> Bool {
        guard let expectedHost = endpoints.accountOrigin.host else { return false }
        return url.scheme == "https" &&
            url.host == expectedHost &&
            url.path == AccountOAuthClaimedCallback.path
    }
}
