import AppKit
import AuthenticationServices
import CryptoKit
import CurfewProtocols
import Foundation

enum AccountOAuthEnrollmentError: Error {
    case invalidClientID
    case invalidState
    case invalidVerifier
    case couldNotBuildAuthorizationURL
    case invalidCallback
    case stateMismatch
    case authorizationRejected
    case invalidResponse
    case missingPresentationAnchor
    case authenticationInProgress
    case browserCompletedConnectionFailed
    case accountMismatch
}

@MainActor
final class AccountOAuthAuthenticationGate {
    private var isActive = false

    func begin() throws {
        guard !isActive else {
            throw AccountOAuthEnrollmentError.authenticationInProgress
        }
        isActive = true
    }

    func finish() {
        isActive = false
    }
}

@MainActor
final class AccountOAuthPresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding {
    weak var settingsWindow: NSWindow?
    private(set) var activePresentationWindow: NSWindow?

    func prepareForPresentation() throws {
        guard let settingsWindow else {
            throw AccountOAuthEnrollmentError.missingPresentationAnchor
        }
        activePresentationWindow = settingsWindow
    }

    func finishPresentation() {
        activePresentationWindow = nil
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        precondition(
            activePresentationWindow != nil,
            "OAuth presentation was requested without the Settings window"
        )
        return activePresentationWindow!
    }
}

struct AccountOAuthTokens: Equatable {
    let accessToken: String
    let refreshToken: String
}

struct AccountOAuthGrant: Equatable {
    let tokens: AccountOAuthTokens
    let state: String
    let codeChallenge: String
    let subjectID: String?

    init(
        tokens: AccountOAuthTokens,
        state: String,
        codeChallenge: String,
        subjectID: String? = nil
    ) {
        self.tokens = tokens
        self.state = state
        self.codeChallenge = codeChallenge
        self.subjectID = subjectID
    }

    init(resourceTokens: AccountOAuthTokens, state: String, codeChallenge: String) {
        self.init(
            tokens: resourceTokens,
            state: state,
            codeChallenge: codeChallenge,
            subjectID: AccountOAuthTokenSubject.extract(from: resourceTokens.accessToken)
        )
    }
}

enum AccountOAuthOfficialClient {
    static let clientID = "curfew-native-client"
}

enum AccountOAuthTokenRequest {
    static func authorizationCodeBody(
        code: String,
        clientID: String,
        verifier: String,
        redirectURI: String,
        resource: String = CurfewServiceEndpoints.current.syncResource.absoluteString
    ) -> Data {
        formBody([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "resource": resource
        ])
    }

    static func refreshBody(
        refreshToken: String,
        clientID: String,
        resource: String = CurfewServiceEndpoints.current.syncResource.absoluteString
    ) -> Data {
        formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": resource
        ])
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let body = fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}

@MainActor
final class AccountOAuthEnrollmentService: NSObject {
    private let secretStore: any AccountSecretStoring
    private let session: URLSession
    private let endpoints: CurfewServiceEndpoints
    private let callbackRouter: any AccountOAuthCallbackRouting
    private let authenticationGate = AccountOAuthAuthenticationGate()
    private let presentationContext = AccountOAuthPresentationContext()
    private var browserSession: ASWebAuthenticationSession?
    private var callbackRegistration: UUID?
    private var authenticationContinuation: CheckedContinuation<URL, any Error>?
    private var cancellationRequested = false

    init(
        secretStore: any AccountSecretStoring = KeychainAccountSecretStore(),
        session: URLSession? = nil,
        endpoints: CurfewServiceEndpoints = .current,
        callbackRouter: (any AccountOAuthCallbackRouting)? = nil
    ) {
        self.secretStore = secretStore
        self.endpoints = endpoints
        self.callbackRouter = callbackRouter ?? AccountOAuthCallbackRouter.shared
        self.session = session ?? URLSession(
            configuration: .ephemeral,
            delegate: RejectingRedirectSessionDelegate(),
            delegateQueue: nil
        )
    }

    func signIn(
        presentationWindow: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        try await authorize(
            presentationWindow: presentationWindow,
            authorizationURLHandler: authorizationURLHandler,
            expectedAccountUserID: nil
        )
    }

    func reauthorize(
        expectedAccountUserID: String,
        presentationWindow: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        try await authorize(
            presentationWindow: presentationWindow,
            authorizationURLHandler: authorizationURLHandler,
            expectedAccountUserID: expectedAccountUserID
        )
    }

    private func authorize(
        presentationWindow: NSWindow?,
        authorizationURLHandler: @escaping @MainActor (URL) -> Void,
        expectedAccountUserID: String?
    ) async throws -> AccountOAuthGrant {
        try authenticationGate.begin()
        defer { authenticationGate.finish() }
        cancellationRequested = false
        try Task.checkCancellation()
        presentationContext.settingsWindow = presentationWindow
        try presentationContext.prepareForPresentation()
        defer { presentationContext.finishPresentation() }
        let clientID = AccountOAuthOfficialClient.clientID
        let request = try AccountOAuthEnrollmentRequest.create(
            clientID: clientID,
            state: Self.randomURLSafe(byteCount: 32),
            verifier: Self.randomURLSafe(byteCount: 64),
            endpoints: endpoints
        )
        authorizationURLHandler(request.authorizationURL)
        let callback = try await authenticate(request)
        let code = try AccountOAuthCallback.authorizationCode(
            from: callback,
            expectedState: request.state,
            expectedRedirectURI: request.redirectURI
        )
        do {
            let tokens = try await exchange(code: code, clientID: clientID, request: request)
            guard !cancellationRequested else { throw CancellationError() }
            try Task.checkCancellation()
            let grant = AccountOAuthGrant(
                resourceTokens: tokens,
                state: request.state,
                codeChallenge: request.codeChallenge
            )
            try await persist(grant, expectedAccountUserID: expectedAccountUserID)
            return grant
        } catch is CancellationError {
            throw CancellationError()
        } catch AccountOAuthEnrollmentError.accountMismatch {
            throw AccountOAuthEnrollmentError.accountMismatch
        } catch {
            if cancellationRequested || Task.isCancelled {
                throw CancellationError()
            }
            throw AccountOAuthEnrollmentError.browserCompletedConnectionFailed
        }
    }

    private func persist(
        _ grant: AccountOAuthGrant,
        expectedAccountUserID: String?
    ) async throws {
        if let expectedAccountUserID {
            try await AccountOAuthReauthorization.commit(
                grant: grant,
                expectedAccountUserID: expectedAccountUserID,
                secretStore: secretStore,
                session: session,
                endpoints: endpoints
            )
        } else {
            try secretStore.save(
                Data(AccountOAuthOfficialClient.clientID.utf8),
                for: "oauth-client-id"
            )
            // Persist the refresh token before its paired access token so an
            // interrupted write cannot expose an access token with no renewal path.
            try secretStore.save(Data(grant.tokens.refreshToken.utf8), for: "oauth-refresh-token")
            try secretStore.save(Data(grant.tokens.accessToken.utf8), for: "oauth-access-token")
        }
    }

    func cancelSignIn() {
        cancellationRequested = true
        finishAuthentication(with: .failure(CancellationError()))
    }

    private func authenticate(_ request: AccountOAuthEnrollmentRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            authenticationContinuation = continuation
            do {
                callbackRegistration = try callbackRouter.register(
                    expectedState: request.state,
                    expectedRedirectURI: request.redirectURI
                ) { [weak self] callback in
                    self?.finishAuthentication(with: .success(callback))
                }
            } catch {
                finishAuthentication(with: .failure(error))
                return
            }
            let browserSession = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callback: AccountOAuthCallbackPolicy.callback(for: endpoints)
            ) { [weak self] callback, error in
                if let callback {
                    self?.finishAuthentication(with: .success(callback))
                } else {
                    self?.finishAuthentication(
                        with: .failure(
                            error ?? AccountOAuthEnrollmentError.authorizationRejected
                        )
                    )
                }
            }
            browserSession.presentationContextProvider = presentationContext
            AccountOAuthBrowserPolicy.configure(browserSession)
            self.browserSession = browserSession
            guard browserSession.start() else {
                finishAuthentication(with: .failure(
                    AccountOAuthEnrollmentError.authorizationRejected
                ))
                return
            }
        }
    }

    private func finishAuthentication(with result: Swift.Result<URL, any Error>) {
        guard let continuation = authenticationContinuation else { return }
        authenticationContinuation = nil
        if let callbackRegistration {
            callbackRouter.unregister(callbackRegistration)
            self.callbackRegistration = nil
        }
        let activeSession = browserSession
        browserSession = nil
        activeSession?.cancel()
        continuation.resume(with: result)
    }

    private func exchange(
        code: String,
        clientID: String,
        request: AccountOAuthEnrollmentRequest
    ) async throws -> AccountOAuthTokens {
        var tokenRequest = URLRequest(url: request.tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.httpBody = AccountOAuthTokenRequest.authorizationCodeBody(
            code: code,
            clientID: clientID,
            verifier: request.verifier,
            redirectURI: request.redirectURI,
            resource: endpoints.syncResource.absoluteString
        )
        tokenRequest.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await AccountOAuthWire.tokens(from: responseData(for: tokenRequest))
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= 32 * 1024
        else { throw AccountOAuthEnrollmentError.invalidResponse }
        return data
    }

    private static func randomURLSafe(byteCount: Int) -> String {
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let accountOrigin = URL(string: "https://curfew-account.hypertext.studio")!
    private static let redirectURI = AccountOAuthClaimedCallback.redirectURI(for: .current)
}
