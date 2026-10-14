import Foundation

/// The complete, closed-world network boundary for one Curfew account environment.
///
/// App, OAuth, sync, MCP, and privileged-daemon traffic must select the same
/// value. App and widget bundle identities select their isolated environment;
/// packaged tools also receive the explicit staging flag. This prevents staging
/// account tokens or command keys from being mixed with production state.
public nonisolated struct CurfewServiceEndpoints: Equatable, Sendable {
    public let siteOrigin: URL
    public let licenseOrigin: URL
    public let appcast: URL
    public let pricingURL: URL
    public let accountOrigin: URL
    public let accountPortal: URL
    public let syncResource: URL
    public let mcpResource: URL
    public let remoteCommandJWKS: URL
    public let keychainService: String

    public static let production = make(
        profile: .production,
        keychainService: "studio.hypertext.curfew.account-e2ee"
    )

    public static let staging = make(
        profile: .staging,
        keychainService: "studio.hypertext.curfew.account-e2ee.staging"
    )

    public static let studioDevelopment = make(
        profile: .staging,
        keychainService: "studio.hypertext.curfew.account-e2ee.studio.dev"
    )

    public static func forFlavor(_ flavor: CurfewFlavor) -> CurfewServiceEndpoints {
        switch flavor {
        case .production: production
        case .development: staging
        case .studioDevelopment: studioDevelopment
        }
    }

    #if CURFEW_STAGING
        public static let current = forFlavor(CurfewFlavor.current)
    #else
        public static let current = forFlavor(CurfewFlavor.resolve(
            environment: [:], bundleIdentifier: Bundle.main.bundleIdentifier,
            executableURL: Bundle.main.executableURL
        ))
    #endif

    private static func make(
        profile: DeploymentProfile,
        keychainService: String
    ) -> CurfewServiceEndpoints {
        let accountOrigin = profile.accountOrigin
        let accountPortal = profile.siteOrigin + "/account"
        let syncOrigin = profile.syncOrigin
        guard let siteURL = URL(string: profile.siteOrigin),
              let licenseURL = URL(string: profile.licenseOrigin),
              let appcastURL = URL(string: profile.siteOrigin + "/appcast.xml"),
              let pricingURL = URL(string: profile.siteOrigin + "/#plus"),
              let accountOriginURL = URL(string: accountOrigin),
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
            siteOrigin: siteURL,
            licenseOrigin: licenseURL,
            appcast: appcastURL,
            pricingURL: pricingURL,
            accountOrigin: accountOriginURL,
            accountPortal: accountPortalURL,
            syncResource: syncResourceURL,
            mcpResource: mcpResourceURL,
            remoteCommandJWKS: remoteCommandJWKSURL,
            keychainService: keychainService
        )
    }
}
