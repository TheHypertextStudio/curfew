import CurfewKit
import Foundation
import LocalAuthentication
import Security
import Testing

private final class MemorySecretStore: AccountSecretStoring {
    var values: [String: Data] = [:]
    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values.removeValue(forKey: account)
    }
}

struct ModuleBoundaryTests {
    @Test func backgroundCredentialQueriesNeverAllowPrompts() throws {
        let query = BackgroundKeychainQuery.read(service: "synthetic", account: "synthetic")
        let context = try #require(query[kSecUseAuthenticationContext] as? LAContext)
        #expect(context.interactionNotAllowed)
    }

    @Test func browserClientsCanReadSessionAndTerminalState() throws {
        let reducer = try BrowserWorkSessionReducer(
            docketWebOrigin: #require(URL(string: "https://example.test")),
            mappings: []
        )
        #expect(reducer.currentTask() == nil)
        #expect(reducer.currentSessionID() == nil)
        #expect(DocketActiveWorkTask.isTerminal("completed"))
    }

    @MainActor @Test func appCanUseCredentialInterfacesWithoutDuplicatingSharedSources() throws {
        let store = DocketCredentialStore(secretStore: MemorySecretStore())
        let tokens = DocketOAuthTokens(
            accessToken: "synthetic-access",
            refreshToken: "synthetic-refresh",
            expiresAt: Date(timeIntervalSince1970: 1000)
        )
        try store.save(tokens)
        #expect(try store.load() == tokens)
        try store.clear()
        #expect(try store.load() == nil)
    }
}
