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

enum AccountOAuthClientRegistration {
    static func requestBody() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "client_name": "Curfew for macOS",
            "token_endpoint_auth_method": "none",
            "application_type": "native",
            "redirect_uris": ["studio.hypertext.curfew://oauth/callback"],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": AccountOAuthEnrollmentRequest.requiredScopes.joined(separator: " "),
            "resources": [FirstPartyResource.httpsCurfewSyncHypertextStudio.rawValue]
        ])
    }
}

enum AccountOAuthTokenRequest {
    static func authorizationCodeBody(
        code: String,
        clientID: String,
        verifier: String,
        redirectURI: String
    ) -> Data {
        formBody([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": FirstPartyResource.httpsCurfewSyncHypertextStudio.rawValue
        ])
    }

    static func refreshBody(refreshToken: String, clientID: String) -> Data {
        formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": FirstPartyResource.httpsCurfewSyncHypertextStudio.rawValue
        ])
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let body = fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
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

@MainActor
final class AccountOAuthTokenRefresher {
    private let secretStore: any AccountSecretStoring
    private let session: URLSession

    init(secretStore: any AccountSecretStoring, session: URLSession) {
        self.secretStore = secretStore
        self.session = session
    }

    func refresh() async throws {
        guard let clientData = try secretStore.data(for: "oauth-client-id"),
              let clientID = String(data: clientData, encoding: .utf8),
              let refreshData = try secretStore.data(for: "oauth-refresh-token"),
              let refreshToken = String(data: refreshData, encoding: .utf8)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        var request = URLRequest(
            url: URL(string: "https://curfew-account.hypertext.studio/api/auth/oauth2/token")!
        )
        request.httpMethod = "POST"
        request.httpBody = AccountOAuthTokenRequest.refreshBody(
            refreshToken: refreshToken,
            clientID: clientID
        )
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode)
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        let tokens = try AccountOAuthWire.tokens(from: data)
        // Persist the rotated credential before exposing its paired access
        // token so a crash cannot strand the account on a spent refresh token.
        try secretStore.save(Data(tokens.refreshToken.utf8), for: "oauth-refresh-token")
        try secretStore.save(Data(tokens.accessToken.utf8), for: "oauth-access-token")
    }
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try AccountOAuthClientRegistration.requestBody()
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
        var tokenRequest = URLRequest(url: request.tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.httpBody = AccountOAuthTokenRequest.authorizationCodeBody(
            code: code,
            clientID: clientID,
            verifier: request.verifier,
            redirectURI: request.redirectURI
        )
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

    private static let accountOrigin = URL(string: "https://curfew-account.hypertext.studio")!
    private static let callbackScheme = "studio.hypertext.curfew"
    private static let redirectURI = "\(callbackScheme)://oauth/callback"
}
