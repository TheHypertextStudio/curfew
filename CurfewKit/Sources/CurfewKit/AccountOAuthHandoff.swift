import Foundation

/// Converts an explicitly opened Curfew account handoff into the HTTPS callback
/// the pending OAuth transaction already expects. The app supplies its own
/// registered scheme and in-memory state; this is not a second OAuth redirect.
public enum AccountOAuthHandoff {
    public static func canonicalCallback(
        from incoming: URL,
        registeredScheme: String,
        expectedRedirectURI: String,
        expectedState: String
    ) -> URL? {
        guard ["studio.hypertext.curfew", "studio.hypertext.curfew.studio.dev"]
            .contains(registeredScheme),
            let source = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
            source.scheme == registeredScheme,
            source.host == "account-oauth",
            source.path == "/callback",
            source.user == nil,
            source.password == nil,
            source.port == nil,
            source.fragment == nil,
            let query = source.queryItems,
            query.count == 2,
            let code = query.first(where: { $0.name == "code" })?.value,
            !code.isEmpty,
            code.count <= 2048,
            let state = query.first(where: { $0.name == "state" })?.value,
            !state.isEmpty,
            state.count <= 256,
            state == expectedState,
            var canonical = URLComponents(string: expectedRedirectURI),
            canonical.scheme == "https",
            canonical.host != nil,
            canonical.user == nil,
            canonical.password == nil,
            canonical.query == nil,
            canonical.fragment == nil
        else { return nil }
        canonical.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "state", value: state)
        ]
        return canonical.url
    }
}
