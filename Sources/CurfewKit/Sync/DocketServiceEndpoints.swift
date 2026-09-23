import Foundation

nonisolated struct DocketServiceEndpoints: Equatable, Sendable {
    let webOrigin: URL
    let mcpResource: URL
    let authorizationEndpoint: URL
    let registrationEndpoint: URL
    let tokenEndpoint: URL
    let keychainService: String

    static let production = make(
        webOrigin: "https://clearthedocket.com",
        apiOrigin: "https://api.clearthedocket.com",
        keychainService: "studio.hypertext.curfew.docket"
    )

    static let staging = make(
        webOrigin: "https://docket-staging.hypertext.studio",
        apiOrigin: "https://docket-api-staging.hypertext.studio",
        keychainService: "studio.hypertext.curfew.docket.staging"
    )

    static let studioDevelopment = make(
        webOrigin: "https://docket-staging.hypertext.studio",
        apiOrigin: "https://docket-api-staging.hypertext.studio",
        keychainService: "studio.hypertext.curfew.docket.studio.dev"
    )

    static func forFlavor(_ flavor: CurfewFlavor) -> DocketServiceEndpoints {
        switch flavor {
        case .production: production
        case .development: staging
        case .studioDevelopment: studioDevelopment
        }
    }

    #if CURFEW_STAGING
        static let current = forFlavor(CurfewFlavor.current)
    #else
        static let current = production
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
