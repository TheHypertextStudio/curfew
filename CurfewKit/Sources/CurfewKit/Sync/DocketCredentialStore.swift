import Foundation

public nonisolated struct DocketOAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

@MainActor
public final class DocketCredentialStore {
    public static let clientIDAccount = "oauth-client-id"
    public static let accessTokenAccount = "oauth-access-token"
    public static let refreshTokenAccount = "oauth-refresh-token"
    public static let expirationAccount = "oauth-expiration"

    private let secretStore: any AccountSecretStoring
    private var cachedTokens: DocketOAuthTokens?
    private var hasLoadedTokens = false
    private var cachedRefreshToken: String?
    private var hasLoadedRefreshToken = false
    private var cachedClientID: String?
    private var hasLoadedClientID = false

    public init(
        secretStore: (any AccountSecretStoring)? = nil,
        endpoints: DocketServiceEndpoints = .current
    ) {
        self.secretStore = secretStore ?? KeychainAccountSecretStore(
            service: endpoints.keychainService
        )
    }

    public func load() throws -> DocketOAuthTokens? {
        if hasLoadedTokens {
            return cachedTokens
        }
        guard let accessData = try secretStore.data(for: Self.accessTokenAccount),
              let accessToken = String(data: accessData, encoding: .utf8),
              let refreshToken = try loadRefreshToken(),
              let expirationData = try secretStore.data(for: Self.expirationAccount),
              let expirationString = String(data: expirationData, encoding: .utf8),
              let expiration = TimeInterval(expirationString)
        else {
            hasLoadedTokens = true
            cachedTokens = nil
            return nil
        }
        let tokens = DocketOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiration)
        )
        cachedTokens = tokens
        hasLoadedTokens = true
        return tokens
    }

    public func loadClientID() throws -> String? {
        if hasLoadedClientID {
            return cachedClientID
        }
        let clientID = try secretStore.data(for: Self.clientIDAccount)
            .flatMap { String(data: $0, encoding: .utf8) }
        cachedClientID = clientID
        hasLoadedClientID = true
        return clientID
    }

    public func saveClientID(_ clientID: String) throws {
        try secretStore.save(Data(clientID.utf8), for: Self.clientIDAccount)
        cachedClientID = clientID
        hasLoadedClientID = true
    }

    public func loadRefreshToken() throws -> String? {
        if hasLoadedRefreshToken {
            return cachedRefreshToken
        }
        let refreshToken = try secretStore.data(for: Self.refreshTokenAccount)
            .flatMap { String(data: $0, encoding: .utf8) }
        cachedRefreshToken = refreshToken
        hasLoadedRefreshToken = true
        return refreshToken
    }

    public func save(_ tokens: DocketOAuthTokens) throws {
        // Save the rotating credential first. A crash cannot leave a spent
        // refresh token paired with a newer access token.
        try secretStore.save(Data(tokens.refreshToken.utf8), for: Self.refreshTokenAccount)
        try secretStore.save(Data(tokens.accessToken.utf8), for: Self.accessTokenAccount)
        try secretStore.save(
            Data(String(tokens.expiresAt.timeIntervalSince1970).utf8),
            for: Self.expirationAccount
        )
        cachedRefreshToken = tokens.refreshToken
        hasLoadedRefreshToken = true
        cachedTokens = tokens
        hasLoadedTokens = true
    }

    public func clear() throws {
        cachedClientID = nil
        hasLoadedClientID = true
        cachedRefreshToken = nil
        hasLoadedRefreshToken = true
        cachedTokens = nil
        hasLoadedTokens = true
        try secretStore.delete(Self.clientIDAccount)
        try secretStore.delete(Self.accessTokenAccount)
        try secretStore.delete(Self.refreshTokenAccount)
        try secretStore.delete(Self.expirationAccount)
    }
}
