import Foundation

/// The complete, closed-world network boundary for one Curfew account environment.
///
/// App, OAuth, sync, MCP, and privileged-daemon traffic must select the same
/// value at compile time. This prevents a staging account token or command key
/// from being mixed with production state.
public nonisolated struct CurfewServiceEndpoints: Equatable, Sendable {
    public let accountOrigin: URL
    public let accountPortal: URL
    public let syncResource: URL
    public let mcpResource: URL
    public let remoteCommandJWKS: URL
    public let keychainService: String

    public static let production = make(
        accountOrigin: "https://curfew-account.hypertext.studio",
        accountPortal: "https://curfew.hypertext.studio/account",
        syncOrigin: "https://curfew-sync.hypertext.studio",
        keychainService: "studio.hypertext.curfew.account-e2ee"
    )

    public static let staging = make(
        accountOrigin: "https://curfew-account-staging.hypertext.studio",
        accountPortal: "https://curfew-staging.hypertext.studio/account",
        syncOrigin: "https://curfew-sync-staging.hypertext.studio",
        keychainService: "studio.hypertext.curfew.account-e2ee.staging"
    )

    #if CURFEW_STAGING
        public static let current = staging
    #else
        public static let current = production
    #endif

    private static func make(
        accountOrigin: String,
        accountPortal: String,
        syncOrigin: String,
        keychainService: String
    ) -> CurfewServiceEndpoints {
        guard let accountOriginURL = URL(string: accountOrigin),
              let accountPortalURL = URL(string: accountPortal),
              let syncResourceURL = URL(string: syncOrigin),
              let mcpResourceURL = URL(string: syncOrigin + "/mcp"),
              let remoteCommandJWKSURL = URL(
                  string: syncOrigin + "/.well-known/curfew-command-jwks.json"
              )
        else {
            preconditionFailure("Curfew service endpoints must be valid HTTPS URLs")
        }
        return CurfewServiceEndpoints(
            accountOrigin: accountOriginURL,
            accountPortal: accountPortalURL,
            syncResource: syncResourceURL,
            mcpResource: mcpResourceURL,
            remoteCommandJWKS: remoteCommandJWKSURL,
            keychainService: keychainService
        )
    }
}
