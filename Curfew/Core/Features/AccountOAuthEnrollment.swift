import AppKit
import AuthenticationServices
import CryptoKit
import CurfewProtocols
import Foundation

enum AccountOAuthEnrollmentError: Error {
    case invalidClientID
    case invalidCallbackScheme
    case invalidState
    case invalidVerifier
    case couldNotBuildAuthorizationURL
    case invalidCallback
    case stateMismatch
    case authorizationRejected
    case invalidResponse
}

enum AccountOAuthCallback {
    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == "studio.hypertext.curfew",
              callback.host == "oauth",
              callback.path == "/callback",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw AccountOAuthEnrollmentError.invalidCallback }
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        guard query["state"] == expectedState else {
            throw AccountOAuthEnrollmentError.stateMismatch
        }
        guard query["error"] == nil,
              let code = query["code"],
              !code.isEmpty
        else { throw AccountOAuthEnrollmentError.authorizationRejected }
        return code
    }
}

struct AccountOAuthRegistration: Equatable {
    let clientID: String
}

struct AccountOAuthTokens: Equatable {
    let accessToken: String
    let refreshToken: String
}

struct AccountOAuthGrant: Equatable {
    let tokens: AccountOAuthTokens
    let state: String
    let codeChallenge: String
}

enum AccountOAuthWire {
    static func registration(from data: Data) throws -> AccountOAuthRegistration {
        guard data.count <= 32 * 1024,
              let response = try? decoder.decode(
                  AccountOAuthRegistrationResponse.self,
                  from: data
              ),
              !response.clientID.isEmpty
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return AccountOAuthRegistration(clientID: response.clientID)
    }

    static func tokens(from data: Data) throws -> AccountOAuthTokens {
        guard data.count <= 32 * 1024,
              let response = try? decoder.decode(AccountOAuthTokenResponse.self, from: data),
              response.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !response.accessToken.isEmpty,
              !response.refreshToken.isEmpty
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return AccountOAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private static let decoder = JSONDecoder()
}

private struct AccountOAuthRegistrationResponse: Decodable {
    let clientID: String
    private enum CodingKeys: String, CodingKey { case clientID = "client_id" }
}

private struct AccountOAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

@MainActor
final class AccountOAuthEnrollmentService: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    private let secretStore: any AccountSecretStoring
    private let session: URLSession
    private var browserSession: ASWebAuthenticationSession?

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil
    ) {
        self.secretStore = secretStore
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
    }

    func signIn() async throws -> AccountOAuthGrant {
        let clientID = try await registeredClientID()
        let request = try AccountOAuthEnrollmentRequest.create(
            clientID: clientID,
            callbackScheme: Self.callbackScheme,
            state: Self.randomURLSafe(byteCount: 32),
            verifier: Self.randomURLSafe(byteCount: 64)
        )
        let callback = try await authenticate(request)
        let code = try AccountOAuthCallback.authorizationCode(
            from: callback,
            expectedState: request.state
        )
        let tokens = try await exchange(code: code, clientID: clientID, request: request)
        try secretStore.save(Data(tokens.accessToken.utf8), for: "oauth-access-token")
        try secretStore.save(Data(tokens.refreshToken.utf8), for: "oauth-refresh-token")
        return AccountOAuthGrant(
            tokens: tokens,
            state: request.state,
            codeChallenge: request.codeChallenge
        )
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }

    private func registeredClientID() async throws -> String {
        if let stored = try secretStore.data(for: "oauth-client-id"),
           let clientID = String(data: stored, encoding: .utf8),
           !clientID.isEmpty {
            return clientID
        }
        let endpoint = Self.accountOrigin.appending(path: "/api/auth/oauth2/register")
        let body = try JSONSerialization.data(withJSONObject: [
            "client_name": "Curfew for macOS",
            "token_endpoint_auth_method": "none",
            "application_type": "native",
            "redirect_uris": [Self.redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": AccountOAuthEnrollmentRequest.requiredScopes.joined(separator: " ")
        ])
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await responseData(for: request)
        let registration = try AccountOAuthWire.registration(from: data)
        try secretStore.save(Data(registration.clientID.utf8), for: "oauth-client-id")
        return registration.clientID
    }

    private func authenticate(_ request: AccountOAuthEnrollmentRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let browserSession = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: Self.callbackScheme
            ) { [weak self] callback, error in
                self?.browserSession = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(
                        throwing: error ?? AccountOAuthEnrollmentError.authorizationRejected
                    )
                }
            }
            browserSession.presentationContextProvider = self
            browserSession.prefersEphemeralWebBrowserSession = true
            self.browserSession = browserSession
            guard browserSession.start() else {
                self.browserSession = nil
                continuation.resume(throwing: AccountOAuthEnrollmentError.authorizationRejected)
                return
            }
        }
    }

    private func exchange(
        code: String,
        clientID: String,
        request: AccountOAuthEnrollmentRequest
    ) async throws -> AccountOAuthTokens {
        let fields = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": request.verifier,
            "redirect_uri": request.redirectURI
        ]
        let body = fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(Self.formEncode(key))=\(Self.formEncode(value))"
        }.joined(separator: "&")
        var tokenRequest = URLRequest(url: request.tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.httpBody = Data(body.utf8)
        tokenRequest.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await AccountOAuthWire.tokens(from: responseData(for: tokenRequest))
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= 32 * 1024
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return data
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    private static let accountOrigin = URL(string: "https://curfew-account.hypertext.studio")!
    private static let callbackScheme = "studio.hypertext.curfew"
    private static let redirectURI = "\(callbackScheme)://oauth/callback"
}

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
        verifier: String
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
            url: Self.accountOrigin.appending(path: "/api/auth/oauth2/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: requiredScopes.joined(separator: " ")),
            URLQueryItem(
                name: "resource",
                value: FirstPartyResource.httpsCurfewSyncHypertextStudio.rawValue
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
            tokenURL: accountOrigin.appending(path: "/api/auth/oauth2/token"),
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

    private static let accountOrigin = URL(string: "https://curfew-account.hypertext.studio")!
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
