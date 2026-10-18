@testable import CurfewKit
import Foundation
import Testing

struct DeploymentEndpointTests {
    @Test func purchaseEntryUsesTheWebsiteWithoutChangingAccountIdentity() {
        for endpoints in [CurfewServiceEndpoints.staging, .development] {
            #expect(endpoints.pricingURL
                .absoluteString == "https://curfew-site-staging.hypertext.studio/#plus")
            #expect(endpoints.accountPortal
                .absoluteString == "https://curfew-staging.hypertext.studio/account")
        }
        #expect(CurfewServiceEndpoints.production.pricingURL
            .absoluteString == "https://thecurfew.app/#plus")
    }

    @Test func productionUsesNewAuthorityAndResource() {
        let endpoints = CurfewServiceEndpoints.production
        #expect(endpoints.accountOrigin.host == "account.thecurfew.app")
        #expect(endpoints.syncResource.absoluteString == "https://sync.thecurfew.app")
        #expect(endpoints.mcpResource.absoluteString == "https://sync.thecurfew.app/mcp")
        #expect(endpoints.remoteCommandJWKS
            .absoluteString == "https://sync.thecurfew.app/.well-known/curfew-command-jwks.json")
        #expect(endpoints.keychainService == "studio.hypertext.curfew.account-e2ee")
    }
}

private final class MigrationSecretStore: AccountSecretStoring, @unchecked Sendable {
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

extension DeploymentEndpointTests {
    @Test func obsoleteAuthorizationIsDiscardedWithoutLosingIdentityOrEncryption() throws {
        let store = MigrationSecretStore()
        try store.save(Data("old-token".utf8), for: "oauth-access-token")
        try store.save(Data("old-refresh".utf8), for: "oauth-refresh-token")
        try store.save(Data("retained-key".utf8), for: "account-encryption-key")
        try store.save(Data("retained-device".utf8), for: "device-id")
        #expect(try AccountDomainAuthorizationMigration.prepare(
            store: store,
            endpoints: .production
        ))
        #expect(try store.data(for: "oauth-access-token") == nil)
        #expect(try store.data(for: "oauth-refresh-token") == nil)
        #expect(try store.data(for: "account-encryption-key") == Data("retained-key".utf8))
        #expect(try store.data(for: "device-id") == Data("retained-device".utf8))
        try store.save(Data("new-token".utf8), for: "oauth-access-token")
        #expect(try !AccountDomainAuthorizationMigration.prepare(
            store: store,
            endpoints: .production
        ))
        #expect(try store.data(for: "oauth-access-token") == Data("new-token".utf8))
    }
}
