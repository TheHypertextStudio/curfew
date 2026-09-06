import CryptoKit
import CurfewProtocols
import Foundation

struct AccountOAuthEnrollmentRequest: Equatable {
    let authorizationURL: URL
    let tokenURL: URL
    let redirectURI: String
    let state: String
    let verifier: String
    let codeChallenge: String

    static func create(
        clientID: String,
        callbackScheme: String,
        state: String,
        verifier: String,
        endpoints: CurfewServiceEndpoints = .current
    ) throws -> AccountOAuthEnrollmentRequest {
        guard !clientID.isEmpty else { throw AccountOAuthEnrollmentError.invalidClientID }
        guard callbackScheme == "studio.hypertext.curfew" else {
            throw AccountOAuthEnrollmentError.invalidCallbackScheme
        }
        guard !state.isEmpty else { throw AccountOAuthEnrollmentError.invalidState }
        guard (43 ... 128).contains(verifier.count),
              verifier.unicodeScalars.allSatisfy(pkceCharacters.contains)
        else { throw AccountOAuthEnrollmentError.invalidVerifier }

        let redirectURI = "\(callbackScheme)://oauth/callback"
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(
            url: endpoints.accountOrigin.appending(path: "/api/auth/oauth2/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: requiredScopes.joined(separator: " ")),
            URLQueryItem(
                name: "resource",
                value: endpoints.syncResource.absoluteString
            ),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components?.url else {
            throw AccountOAuthEnrollmentError.couldNotBuildAuthorizationURL
        }
        return AccountOAuthEnrollmentRequest(
            authorizationURL: authorizationURL,
            tokenURL: endpoints.accountOrigin.appending(path: "/api/auth/oauth2/token"),
            redirectURI: redirectURI,
            state: state,
            verifier: verifier,
            codeChallenge: challenge
        )
    }

    static let requiredScopes = [
        "openid",
        "offline_access",
        CurfewFirstPartyOAuthScope.curfewAccountRead.rawValue,
        CurfewFirstPartyOAuthScope.curfewDevicesRead.rawValue,
        CurfewFirstPartyOAuthScope.curfewDevicesWrite.rawValue,
        CurfewFirstPartyOAuthScope.curfewEntitlementsRead.rawValue,
        CurfewFirstPartyOAuthScope.curfewSyncRead.rawValue,
        CurfewFirstPartyOAuthScope.curfewSyncWrite.rawValue,
        CurfewFirstPartyOAuthScope.curfewWakeRead.rawValue,
        CurfewFirstPartyOAuthScope.curfewWakeWrite.rawValue
    ]

    private static let pkceCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    private static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
