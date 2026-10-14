import Foundation

/// Changes network authorization without replacing local identity or encryption material.
public enum AccountDomainAuthorizationMigration {
    @discardableResult
    public static func prepare(
        store: any AccountSecretStoring,
        endpoints: CurfewServiceEndpoints
    ) throws -> Bool {
        guard endpoints == .production else { return false }
        let identity =
            Data((endpoints.accountOrigin.absoluteString + "|" + endpoints.syncResource
                    .absoluteString).utf8)
        let marker = "oauth-deployment-identity"
        guard try store.data(for: marker) != identity else { return false }
        let hadAuthorization = try store.data(for: "oauth-access-token") != nil
            || store.data(for: "oauth-refresh-token") != nil
        for key in [
            "oauth-access-token",
            "oauth-refresh-token",
            "oauth-client-id",
            "pending-account-authorized-connection"
        ] {
            try store.delete(key)
        }
        // Write last: interrupted deletion retries instead of accepting a partial migration.
        try store.save(identity, for: marker)
        return hadAuthorization
    }
}
