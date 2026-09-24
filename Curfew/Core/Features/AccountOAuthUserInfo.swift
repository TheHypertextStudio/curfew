import Foundation

/// This is an unverified hint until the coordinator accepts the access token.
enum AccountOAuthTokenSubject {
    static func extract(from token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        let payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload + String(
            repeating: "=",
            count: (4 - payload.count % 4) % 4
        )),
            data.count <= 32 * 1024,
            let claims = try? JSONDecoder().decode(Claims.self, from: data),
            !claims.sub.isEmpty,
            claims.sub.utf8.count <= 256
        else { return nil }
        return claims.sub
    }

    private struct Claims: Decodable {
        let sub: String
    }
}

enum AccountOAuthUserInfo {
    static func subject(
        accessToken: String,
        session: URLSession,
        endpoints: CurfewServiceEndpoints = .current
    ) async throws -> String {
        guard !accessToken.isEmpty else { throw AccountOAuthEnrollmentError.invalidResponse }
        var request = URLRequest(
            url: endpoints.accountOrigin.appending(path: "/api/auth/oauth2/userinfo")
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              data.count <= 32 * 1024,
              let claims = try? JSONDecoder().decode(Claims.self, from: data),
              !claims.sub.isEmpty,
              claims.sub.utf8.count <= 256
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return claims.sub
    }

    private struct Claims: Decodable {
        let sub: String
    }
}

enum AccountOAuthReauthorization {
    static func commit(
        grant: AccountOAuthGrant,
        expectedAccountUserID: String,
        secretStore: any AccountSecretStoring,
        session: URLSession,
        endpoints: CurfewServiceEndpoints = .current
    ) async throws {
        let actualUserID = try await AccountOAuthUserInfo.subject(
            accessToken: grant.tokens.accessToken,
            session: session,
            endpoints: endpoints
        )
        guard actualUserID == expectedAccountUserID else {
            throw AccountOAuthEnrollmentError.accountMismatch
        }
        try Task.checkCancellation()
        try secretStore.save(
            Data(AccountOAuthOfficialClient.clientID.utf8),
            for: "oauth-client-id"
        )
        try secretStore.save(Data(grant.tokens.refreshToken.utf8), for: "oauth-refresh-token")
        try secretStore.save(Data(grant.tokens.accessToken.utf8), for: "oauth-access-token")
    }
}
