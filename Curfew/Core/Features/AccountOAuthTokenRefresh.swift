import Foundation

enum AccountOAuthWire {
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
    private let endpoints: CurfewServiceEndpoints

    init(
        secretStore: any AccountSecretStoring,
        session: URLSession,
        endpoints: CurfewServiceEndpoints = .current
    ) {
        self.secretStore = secretStore
        self.session = session
        self.endpoints = endpoints
    }

    func refresh() async throws {
        guard let clientData = try secretStore.data(for: "oauth-client-id"),
              let clientID = String(data: clientData, encoding: .utf8),
              let refreshData = try secretStore.data(for: "oauth-refresh-token"),
              let refreshToken = String(data: refreshData, encoding: .utf8)
        else { throw AccountOAuthTokenRefreshError.missingCredentials }
        var request = URLRequest(
            url: endpoints.accountOrigin.appending(path: "/api/auth/oauth2/token")
        )
        request.httpMethod = "POST"
        request.httpBody = AccountOAuthTokenRequest.refreshBody(
            refreshToken: refreshToken,
            clientID: clientID,
            resource: endpoints.syncResource.absoluteString
        )
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AccountOAuthTokenRefreshError.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            if [400, 401, 403].contains(response.statusCode) {
                throw AccountOAuthTokenRefreshError.rejected(response.statusCode)
            }
            throw AccountOAuthTokenRefreshError.invalidResponse
        }
        let tokens = try AccountOAuthWire.tokens(from: data)
        // Persist the rotated credential before exposing its paired access
        // token so a crash cannot strand the account on a spent refresh token.
        try secretStore.save(Data(tokens.refreshToken.utf8), for: "oauth-refresh-token")
        try secretStore.save(Data(tokens.accessToken.utf8), for: "oauth-access-token")
    }
}

enum AccountOAuthTokenRefreshError: Error {
    case missingCredentials
    case rejected(Int)
    case invalidResponse
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
