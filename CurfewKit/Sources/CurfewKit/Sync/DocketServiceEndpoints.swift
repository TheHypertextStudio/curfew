import Foundation

public nonisolated struct DocketServiceEndpoints: Equatable, Sendable {
    public let webOrigin: URL
    public let mcpResource: URL
    public let authorizationEndpoint: URL
    public let registrationEndpoint: URL
    public let tokenEndpoint: URL
    public let keychainService: String

    public static let production = make(
        webOrigin: "https://clearthedocket.com",
        apiOrigin: "https://api.clearthedocket.com",
        keychainService: "studio.hypertext.curfew.docket"
    )

    public static let staging = make(
        webOrigin: "https://docket-staging.hypertext.studio",
        apiOrigin: "https://docket-api-staging.hypertext.studio",
        keychainService: "studio.hypertext.curfew.docket.staging"
    )

    public static let studioDevelopment = make(
        webOrigin: "https://docket-staging.hypertext.studio",
        apiOrigin: "https://docket-api-staging.hypertext.studio",
        keychainService: "studio.hypertext.curfew.docket.studio.dev"
    )

    public static func forFlavor(_ flavor: CurfewFlavor) -> DocketServiceEndpoints {
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
        webOrigin: String,
        apiOrigin: String,
        keychainService: String
    ) -> DocketServiceEndpoints {
        guard let webURL = URL(string: webOrigin),
              let apiURL = URL(string: apiOrigin)
        else { preconditionFailure("Docket endpoints must be valid HTTPS URLs") }
        return DocketServiceEndpoints(
            webOrigin: webURL,
            mcpResource: apiURL.appending(path: "/mcp"),
            authorizationEndpoint: webURL.appending(path: "/api/auth/oauth2/authorize"),
            registrationEndpoint: apiURL.appending(path: "/api/auth/oauth2/register"),
            tokenEndpoint: apiURL.appending(path: "/api/auth/oauth2/token"),
            keychainService: keychainService
        )
    }
}
