@testable import CurfewKit
import Foundation
import Testing

@Suite("Docket credential store")
@MainActor
struct DocketCredentialStoreTests {
    @Test("Loads each token from persistence once per process")
    func loadsTokensOnce() throws {
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = CountingSecretStore(values: [
            DocketCredentialStore.accessTokenAccount: Data("access".utf8),
            DocketCredentialStore.refreshTokenAccount: Data("refresh".utf8),
            DocketCredentialStore.expirationAccount:
                Data(String(expiration.timeIntervalSince1970).utf8)
        ])
        let store = DocketCredentialStore(secretStore: persistence)

        #expect(try store.load() == DocketOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: expiration
        ))
        #expect(try store.load()?.accessToken == "access")
        #expect(persistence.reads == [
            DocketCredentialStore.accessTokenAccount: 1,
            DocketCredentialStore.refreshTokenAccount: 1,
            DocketCredentialStore.expirationAccount: 1
        ])
    }

    @Test("Loads a refresh token without requiring an access-token record")
    func loadsRefreshTokenIndependently() throws {
        let persistence = CountingSecretStore(values: [
            DocketCredentialStore.refreshTokenAccount: Data("refresh".utf8)
        ])
        let store = DocketCredentialStore(secretStore: persistence)

        #expect(try store.loadRefreshToken() == "refresh")
        #expect(try store.loadRefreshToken() == "refresh")
        #expect(try store.load() == nil)
        #expect(persistence.reads == [
            DocketCredentialStore.accessTokenAccount: 1,
            DocketCredentialStore.refreshTokenAccount: 1
        ])
    }

    @Test("Refresh saves replace the process cache")
    func saveReplacesCache() throws {
        let persistence = CountingSecretStore()
        let store = DocketCredentialStore(secretStore: persistence)
        let tokens = DocketOAuthTokens(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        try store.save(tokens)

        #expect(try store.load() == tokens)
        #expect(persistence.reads.isEmpty)
    }

    @Test("Client registration is cached separately from OAuth tokens")
    func cachesClientID() throws {
        let persistence = CountingSecretStore(values: [
            DocketCredentialStore.clientIDAccount: Data("client".utf8)
        ])
        let store = DocketCredentialStore(secretStore: persistence)

        #expect(try store.loadClientID() == "client")
        #expect(try store.loadClientID() == "client")
        #expect(persistence.reads == [DocketCredentialStore.clientIDAccount: 1])
    }

    @Test("Disconnect clears persistence and every cached credential")
    func clearInvalidatesCache() throws {
        let persistence = CountingSecretStore()
        let store = DocketCredentialStore(secretStore: persistence)
        try store.saveClientID("client")
        try store.save(DocketOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        ))

        try store.clear()

        #expect(try store.load() == nil)
        #expect(try store.loadClientID() == nil)
        #expect(Set(persistence.deletes) == Set([
            DocketCredentialStore.clientIDAccount,
            DocketCredentialStore.accessTokenAccount,
            DocketCredentialStore.refreshTokenAccount,
            DocketCredentialStore.expirationAccount
        ]))
    }

    @Test("A failed persistent delete still invalidates the process cache")
    func failedClearInvalidatesCache() throws {
        let persistence = CountingSecretStore(
            deleteFailure: DocketCredentialStore.clientIDAccount
        )
        let store = DocketCredentialStore(secretStore: persistence)
        try store.saveClientID("client")
        try store.save(DocketOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        ))

        #expect(throws: SecretStoreFailure.delete) {
            try store.clear()
        }

        #expect(try store.load() == nil)
        #expect(try store.loadClientID() == nil)
        #expect(persistence.reads.isEmpty)
    }
}

private final class CountingSecretStore: AccountSecretStoring {
    private var values: [String: Data]
    private let deleteFailure: String?
    private(set) var reads: [String: Int] = [:]
    private(set) var deletes: [String] = []

    init(values: [String: Data] = [:], deleteFailure: String? = nil) {
        self.values = values
        self.deleteFailure = deleteFailure
    }

    func data(for account: String) throws -> Data? {
        reads[account, default: 0] += 1
        return values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        if account == deleteFailure {
            throw SecretStoreFailure.delete
        }
        values.removeValue(forKey: account)
        deletes.append(account)
    }
}

private enum SecretStoreFailure: Error {
    case delete
}
