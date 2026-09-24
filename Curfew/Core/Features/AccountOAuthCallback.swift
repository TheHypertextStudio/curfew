import Foundation

enum AccountOAuthCallback {
    static func matchesPendingRequest(
        _ callback: URL,
        expectedState: String,
        expectedRedirectURI: String
    ) -> Bool {
        guard let expected = URL(string: expectedRedirectURI),
              callback.scheme == "https",
              callback.scheme == expected.scheme,
              callback.host == expected.host,
              callback.path == expected.path,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              uniqueQueryValue(named: "state", in: components) == expectedState
        else { return false }
        return true
    }

    static func authorizationCode(
        from callback: URL,
        expectedState: String,
        expectedRedirectURI: String
    ) throws -> String {
        guard matchesPendingRequest(
            callback,
            expectedState: expectedState,
            expectedRedirectURI: expectedRedirectURI
        ),
            let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw AccountOAuthEnrollmentError.invalidCallback }
        guard queryValues(named: "error", in: components).isEmpty,
              let code = uniqueQueryValue(named: "code", in: components),
              !code.isEmpty
        else { throw AccountOAuthEnrollmentError.authorizationRejected }
        return code
    }

    private static func uniqueQueryValue(
        named name: String,
        in components: URLComponents
    ) -> String? {
        let values = queryValues(named: name, in: components)
        guard values.count == 1 else { return nil }
        return values[0].value
    }

    private static func queryValues(
        named name: String,
        in components: URLComponents
    ) -> [URLQueryItem] {
        (components.queryItems ?? []).filter { $0.name == name }
    }
}

@MainActor
protocol AccountOAuthCallbackRouting: AnyObject {
    func register(
        expectedState: String,
        expectedRedirectURI: String,
        handler: @escaping @MainActor (URL) -> Void
    ) throws -> UUID
    func unregister(_ registration: UUID)
    @discardableResult func route(_ callback: URL) -> Bool
}

@MainActor
final class AccountOAuthCallbackRouter: AccountOAuthCallbackRouting {
    static let shared = AccountOAuthCallbackRouter()

    private struct PendingCallback {
        let registration: UUID
        let expectedState: String
        let expectedRedirectURI: String
        let handler: @MainActor (URL) -> Void
    }

    private var pending: PendingCallback?

    func register(
        expectedState: String,
        expectedRedirectURI: String,
        handler: @escaping @MainActor (URL) -> Void
    ) throws -> UUID {
        guard pending == nil else {
            throw AccountOAuthEnrollmentError.authenticationInProgress
        }
        let registration = UUID()
        pending = PendingCallback(
            registration: registration,
            expectedState: expectedState,
            expectedRedirectURI: expectedRedirectURI,
            handler: handler
        )
        return registration
    }

    func unregister(_ registration: UUID) {
        guard pending?.registration == registration else { return }
        pending = nil
    }

    @discardableResult
    func route(_ callback: URL) -> Bool {
        guard let pending,
              AccountOAuthCallback.matchesPendingRequest(
                  callback,
                  expectedState: pending.expectedState,
                  expectedRedirectURI: pending.expectedRedirectURI
              )
        else { return false }
        self.pending = nil
        pending.handler(callback)
        return true
    }
}
