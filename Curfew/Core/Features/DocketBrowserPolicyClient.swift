import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

// swiftlint:disable file_length

enum DocketClientError: Error, Equatable {
    case invalidOAuthRequest
    case invalidResponse
    case unauthorized
    case unavailable
    case staleSession
}

nonisolated struct DocketOAuthAuthorizationRequest: Equatable, Sendable {
    let authorizationURL: URL
    let clientID: String
    let redirectURI: String
    let state: String
    let verifier: String

    static let scopes = ["work:read", "agents:run", "offline_access"]
    static let callbackScheme = "studio.hypertext.curfew"

    static func create(
        clientID: String,
        state: String,
        verifier: String,
        endpoints: DocketServiceEndpoints = .current
    ) throws -> DocketOAuthAuthorizationRequest {
        guard !clientID.isEmpty, !state.isEmpty, (43 ... 128).contains(verifier.count) else {
            throw DocketClientError.invalidOAuthRequest
        }
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirectURI = "\(callbackScheme)://docket-oauth/callback"
        var components = URLComponents(
            url: endpoints.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "resource", value: endpoints.mcpResource.absoluteString),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components?.url else {
            throw DocketClientError.invalidOAuthRequest
        }
        return .init(
            authorizationURL: authorizationURL,
            clientID: clientID,
            redirectURI: redirectURI,
            state: state,
            verifier: verifier
        )
    }

    private static func base64URL(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

nonisolated enum DocketOAuthCallback {
    static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        guard callback.scheme == DocketOAuthAuthorizationRequest.callbackScheme,
              callback.host == "docket-oauth",
              callback.path == "/callback",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        else { throw DocketClientError.invalidResponse }
        let queryItems = components.queryItems ?? []
        let securityNames = ["state", "code", "error"]
        guard securityNames.allSatisfy({ name in
            queryItems.filter { $0.name == name }.count <= 1
        }) else { throw DocketClientError.invalidResponse }
        let state = queryItems.first { $0.name == "state" }?.value
        let code = queryItems.first { $0.name == "code" }?.value
        let error = queryItems.first { $0.name == "error" }?.value
        guard state == expectedState,
              error == nil,
              let code,
              !code.isEmpty
        else { throw DocketClientError.invalidResponse }
        return code
    }
}

@MainActor
protocol DocketOAuthAuthorizing: AnyObject {
    func connect(at date: Date) async throws -> DocketOAuthTokens
    func refresh(now: Date) async throws -> DocketOAuthTokens
}

@MainActor
final class DocketOAuthClient: NSObject, DocketOAuthAuthorizing,
    ASWebAuthenticationPresentationContextProviding {
    private let store: DocketCredentialStore
    private let session: URLSession
    private let endpoints: DocketServiceEndpoints
    private var browserSession: ASWebAuthenticationSession?

    init(
        store: DocketCredentialStore? = nil,
        session: URLSession? = nil,
        endpoints: DocketServiceEndpoints = .current
    ) {
        self.store = store ?? DocketCredentialStore(endpoints: endpoints)
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.endpoints = endpoints
        super.init()
    }

    func connect(at date: Date) async throws -> DocketOAuthTokens {
        let request = try await makeAuthorizationRequest(
            state: Self.randomURLSafe(byteCount: 32),
            verifier: Self.randomURLSafe(byteCount: 64)
        )
        let callback = try await authenticate(request)
        let code = try DocketOAuthCallback.authorizationCode(
            from: callback,
            expectedState: request.state
        )
        return try await exchange(code: code, request: request, now: date)
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }

    func exchange(
        code: String,
        request: DocketOAuthAuthorizationRequest,
        now: Date
    ) async throws -> DocketOAuthTokens {
        try await requestTokens(fields: [
            "grant_type": "authorization_code",
            "client_id": request.clientID,
            "code": code,
            "code_verifier": request.verifier,
            "redirect_uri": request.redirectURI,
            "resource": endpoints.mcpResource.absoluteString
        ], now: now)
    }

    func refresh(now: Date) async throws -> DocketOAuthTokens {
        guard let clientID = try store.loadClientID(),
              let refreshToken = try store.loadRefreshToken()
        else {
            throw DocketClientError.unauthorized
        }
        return try await requestTokens(fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "resource": endpoints.mcpResource.absoluteString
        ], now: now)
    }

    func registerClientIfNeeded() async throws -> String {
        if let clientID = try store.loadClientID(), !clientID.isEmpty {
            return clientID
        }
        var request = URLRequest(url: endpoints.registrationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "Curfew for macOS",
            "redirect_uris": ["studio.hypertext.curfew://docket-oauth/callback"],
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "scope": DocketOAuthAuthorizationRequest.scopes.joined(separator: " ")
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              data.count <= Self.maximumOAuthResponseBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientID = object["client_id"] as? String,
              !clientID.isEmpty
        else { throw DocketClientError.invalidResponse }
        try store.saveClientID(clientID)
        return clientID
    }

    func makeAuthorizationRequest(state: String, verifier: String) async throws
        -> DocketOAuthAuthorizationRequest {
        let clientID = try await registerClientIfNeeded()
        return try DocketOAuthAuthorizationRequest.create(
            clientID: clientID,
            state: state,
            verifier: verifier,
            endpoints: endpoints
        )
    }

    private func requestTokens(fields: [String: String], now: Date) async throws
        -> DocketOAuthTokens {
        var request = URLRequest(url: endpoints.tokenEndpoint)
        request.httpMethod = "POST"
        request.httpBody = Self.formBody(fields)
        request.setValue(
            "application/x-www-form-urlencoded; charset=UTF-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              data.count <= Self.maximumOAuthResponseBytes
        else { throw DocketClientError.invalidResponse }
        let wire = try JSONDecoder().decode(DocketTokenResponse.self, from: data)
        guard wire.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              !wire.accessToken.isEmpty,
              !wire.refreshToken.isEmpty,
              wire.expiresIn > 0
        else { throw DocketClientError.invalidResponse }
        let tokens = DocketOAuthTokens(
            accessToken: wire.accessToken,
            refreshToken: wire.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(wire.expiresIn))
        )
        try store.save(tokens)
        return tokens
    }

    private func authenticate(_ request: DocketOAuthAuthorizationRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let browserSession = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: DocketOAuthAuthorizationRequest.callbackScheme
            ) { [weak self] callback, error in
                self?.browserSession = nil
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? DocketClientError.unauthorized)
                }
            }
            browserSession.presentationContextProvider = self
            browserSession.prefersEphemeralWebBrowserSession = true
            self.browserSession = browserSession
            guard browserSession.start() else {
                self.browserSession = nil
                continuation.resume(throwing: DocketClientError.unauthorized)
                return
            }
        }
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let value = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")
        return Data(value.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
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

    private static let maximumOAuthResponseBytes = 32 * 1024
}

private nonisolated struct DocketTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

nonisolated struct DocketTaskStateObservation: Equatable, Sendable {
    let taskID: String
    let stateType: String
    let archivedAt: Date?
    let observedAt: Date

    init(taskID: String, stateType: String, archivedAt: Date? = nil, observedAt: Date) {
        self.taskID = taskID
        self.stateType = stateType
        self.archivedAt = archivedAt
        self.observedAt = observedAt
    }

    var isTerminal: Bool {
        archivedAt != nil || DocketActiveWorkTask.isTerminal(stateType)
    }
}

nonisolated struct DocketDestinationReviewInput: Codable, Equatable, Sendable {
    struct Destination: Codable, Equatable, Sendable {
        let origin: String
        let path: String
    }

    let organizationID: String
    let taskID: String
    let destination: Destination
    let justification: String
    let challengeAnswer: String?

    private enum CodingKeys: String, CodingKey {
        case destination, justification, challengeAnswer
        case organizationID = "organizationId"
        case taskID = "taskId"
    }
}

nonisolated enum DocketDestinationReview: Equatable, Sendable {
    case grant(reason: String, scope: BrowserDestinationScope)
    case challenge(reason: String, question: String)
    case deny(reason: String)

    var isGrant: Bool {
        if case .grant = self {
            return true
        }
        return false
    }
}

nonisolated enum DocketMCPWire {
    static func decodeActiveWork(_ data: Data) throws -> DocketActiveWork {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.iso8601.date(from: value) ?? Self.iso8601Fractional
                .date(from: value)
            else { throw DocketClientError.invalidResponse }
            return date
        }
        let work = try decoder.decode(DocketActiveWork.self, from: data)
        guard work.schemaVersion == "active-work/1" else {
            throw DocketClientError.invalidResponse
        }
        return work
    }

    static func decodeReview(_ data: Data) throws -> DocketDestinationReview {
        let object = try jsonObject(data)
        guard let decision = object["decision"] as? String,
              let reason = object["reason"] as? String,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw DocketClientError.invalidResponse }
        let hasScope = object.keys.contains("scope")
        let hasQuestion = object.keys.contains("question")
        switch decision {
        case "grant":
            guard !hasQuestion,
                  let scope = object["scope"] as? [String: Any],
                  let kind = scope["kind"] as? String,
                  let value = scope["value"] as? String,
                  !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw DocketClientError.invalidResponse }
            if kind == "origin" {
                return try .grant(
                    reason: reason,
                    scope: BrowserDestinationScope.validatedOrigin(value)
                )
            }
            guard kind == "path_prefix",
                  let scope = try? BrowserDestinationScope.validatedPathPrefix(value)
            else { throw DocketClientError.invalidResponse }
            return .grant(reason: reason, scope: scope)
        case "challenge":
            guard !hasScope,
                  let question = object["question"] as? String,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw DocketClientError.invalidResponse
            }
            return .challenge(reason: reason, question: question)
        case "deny":
            guard !hasScope, !hasQuestion else {
                throw DocketClientError.invalidResponse
            }
            return .deny(reason: reason)
        default:
            throw DocketClientError.invalidResponse
        }
    }

    static func decodeTaskState(_ data: Data, observedAt: Date) throws
        -> DocketTaskStateObservation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.iso8601.date(from: value) ?? Self.iso8601Fractional
                .date(from: value)
            else { throw DocketClientError.invalidResponse }
            return date
        }
        let wire = try decoder.decode(DocketTaskStateWire.self, from: data)
        return .init(
            taskID: wire.id,
            stateType: wire.stateType,
            archivedAt: wire.archivedAt,
            observedAt: observedAt
        )
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocketClientError.invalidResponse
        }
        return object
    }

    private static let iso8601 = ISO8601DateFormatter()
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct DocketTaskStateWire: Decodable {
        let id: String
        let stateType: String
        let archivedAt: Date?
    }
}

nonisolated protocol DocketMCPTransporting: Sendable {
    func readActiveWork(accessToken: String) async throws -> DocketActiveWork
    func readTaskState(
        organizationID: String,
        taskID: String,
        accessToken: String
    ) async throws -> DocketTaskStateObservation
    func reviewDestination(
        _ input: DocketDestinationReviewInput,
        accessToken: String
    ) async throws -> DocketDestinationReview
    func resetSession() async
}

extension DocketMCPTransporting {
    func resetSession() async {}
}

// swiftlint:disable:next type_body_length
actor DocketMCPHTTPTransport: DocketMCPTransporting {
    private let endpoint: URL
    private let session: URLSession
    private var sessionID: String?
    private var requestID = 0
    private var initializationIsInProgress = false
    private var initializationWaiters: [CheckedContinuation<String, any Error>] = []

    init(
        endpoint: URL = DocketServiceEndpoints.current.mcpResource,
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func resetSession() {
        sessionID = nil
    }

    func readActiveWork(accessToken: String) async throws -> DocketActiveWork {
        let result = try await call(
            method: "resources/read",
            parameters: ["uri": "docket://hub/active-work"],
            accessToken: accessToken
        )
        return try DocketMCPWire.decodeActiveWork(resourceText(from: result))
    }

    func readTaskState(
        organizationID: String,
        taskID: String,
        accessToken: String
    ) async throws -> DocketTaskStateObservation {
        let result = try await call(
            method: "resources/read",
            parameters: ["uri": "docket://\(organizationID)/task/\(taskID)"],
            accessToken: accessToken
        )
        return try DocketMCPWire.decodeTaskState(resourceText(from: result), observedAt: Date())
    }

    func reviewDestination(
        _ input: DocketDestinationReviewInput,
        accessToken: String
    ) async throws -> DocketDestinationReview {
        let inputData = try JSONEncoder().encode(input)
        let arguments = try jsonObject(inputData)
        let result = try await call(
            method: "tools/call",
            parameters: [
                "name": "review_work_destination",
                "arguments": arguments
            ],
            accessToken: accessToken
        )
        if result["isError"] as? Bool == true {
            throw DocketClientError.unavailable
        }
        if let structured = result["structuredContent"] as? [String: Any] {
            return try DocketMCPWire
                .decodeReview(JSONSerialization.data(withJSONObject: structured))
        }
        return try DocketMCPWire.decodeReview(toolText(from: result))
    }

    private func call(
        method: String,
        parameters: [String: Any],
        accessToken: String
    ) async throws -> [String: Any] {
        do {
            return try await callOnce(
                method: method,
                parameters: parameters,
                accessToken: accessToken
            )
        } catch DocketClientError.staleSession {
            sessionID = nil
            return try await callOnce(
                method: method,
                parameters: parameters,
                accessToken: accessToken
            )
        }
    }

    private func callOnce(
        method: String,
        parameters: [String: Any],
        accessToken: String
    ) async throws -> [String: Any] {
        let establishedSession = try await establishSession(accessToken: accessToken)
        let response = try await post(
            method: method,
            parameters: parameters,
            accessToken: accessToken,
            sessionID: establishedSession
        )
        guard let result = response.result else { throw DocketClientError.invalidResponse }
        return result
    }

    private func post(
        method: String,
        parameters: [String: Any],
        accessToken: String,
        sessionID: String?
    ) async throws -> (result: [String: Any]?, sessionID: String?) {
        requestID += 1
        let expectedRequestID = requestID
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": expectedRequestID,
            "method": method,
            "params": parameters
        ]
        let (data, http) = try await send(body, accessToken: accessToken, sessionID: sessionID)
        let payload = try Self.responsePayload(data, response: http)
        let envelope = try jsonObject(payload)
        guard envelope["jsonrpc"] as? String == "2.0",
              envelope["error"] == nil,
              (envelope["id"] as? NSNumber)?.intValue == expectedRequestID
        else { throw DocketClientError.invalidResponse }
        return (
            envelope["result"] as? [String: Any],
            http.value(forHTTPHeaderField: "Mcp-Session-Id")
        )
    }

    private func establishSession(accessToken: String) async throws -> String {
        if let sessionID {
            return sessionID
        }
        if initializationIsInProgress {
            return try await withCheckedThrowingContinuation { continuation in
                initializationWaiters.append(continuation)
            }
        }

        initializationIsInProgress = true
        do {
            let initialized = try await post(
                method: "initialize",
                parameters: [
                    "protocolVersion": Self.protocolVersion,
                    "capabilities": [:] as [String: Any],
                    "clientInfo": ["name": "Curfew", "version": "1"]
                ],
                accessToken: accessToken,
                sessionID: nil
            )
            guard initialized.result?["protocolVersion"] as? String == Self.protocolVersion,
                  let establishedSession = initialized.sessionID
            else { throw DocketClientError.invalidResponse }
            _ = try await postNotification(
                method: "notifications/initialized",
                accessToken: accessToken,
                sessionID: establishedSession
            )
            sessionID = establishedSession
            finishInitialization(with: .success(establishedSession))
            return establishedSession
        } catch {
            finishInitialization(with: .failure(error))
            throw error
        }
    }

    private func finishInitialization(with result: Result<String, any Error>) {
        initializationIsInProgress = false
        let waiters = initializationWaiters
        initializationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func postNotification(
        method: String,
        accessToken: String,
        sessionID: String
    ) async throws -> HTTPURLResponse {
        let body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        return try await send(body, accessToken: accessToken, sessionID: sessionID).1
    }

    private func send(
        _ body: [String: Any],
        accessToken: String,
        sessionID: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DocketClientError.invalidResponse
        }
        if http.statusCode == 401 {
            throw DocketClientError.unauthorized
        }
        if sessionID != nil, http.statusCode == 404 || http.statusCode == 410 {
            throw DocketClientError.staleSession
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw DocketClientError.unavailable
        }
        guard data.count <= Self.maximumMCPResponseBytes else {
            throw DocketClientError.invalidResponse
        }
        return (data, http)
    }

    private func resourceText(from result: [String: Any]) throws -> Data {
        guard let contents = result["contents"] as? [[String: Any]],
              let text = contents.first?["text"] as? String
        else { throw DocketClientError.invalidResponse }
        return Data(text.utf8)
    }

    private func toolText(from result: [String: Any]) throws -> Data {
        guard let contents = result["content"] as? [[String: Any]],
              let text = contents.first?["text"] as? String
        else { throw DocketClientError.invalidResponse }
        return Data(text.utf8)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DocketClientError.invalidResponse
        }
        return result
    }

    private nonisolated static func responsePayload(
        _ data: Data,
        response: HTTPURLResponse
    ) throws -> Data {
        guard response.value(forHTTPHeaderField: "Content-Type")?
            .lowercased().contains("text/event-stream") == true
        else { return data }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocketClientError.invalidResponse
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let events = normalized.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard events.count == 1 else { throw DocketClientError.invalidResponse }
        let lines = events[0].split(separator: "\n", omittingEmptySubsequences: false)
        let eventLines = lines.filter { $0.hasPrefix("event:") }
        let dataLines = lines.filter { $0.hasPrefix("data:") }
        guard eventLines.count == 1,
              eventLines[0].dropFirst("event:".count).trimmingCharacters(in: .whitespaces) ==
              "message",
              dataLines.count == 1
        else { throw DocketClientError.invalidResponse }
        let payload = dataLines[0].dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { throw DocketClientError.invalidResponse }
        return Data(payload.utf8)
    }

    /// Docket's browser-policy messages are small. One MiB leaves room for task
    /// context growth while bounding authenticated JSON and SSE parsing.
    private static let maximumMCPResponseBytes = 1024 * 1024
    private static let protocolVersion = "2025-11-25"
}

@MainActor
// swiftlint:disable:next type_body_length
final class DocketBrowserPolicyCoordinator {
    var onPolicyChanged: ((BrowserPolicySnapshot?) -> Void)?
    var onAuthenticatedPoll: ((Date) -> Void)?
    private(set) var hasConfirmedPolicyObservation = false
    private(set) var lastSuccessfulPoll: Date?
    private(set) var lastPollIsHealthy = false
    private(set) var retainedSessionIdentity: BrowserRetainedSessionIdentity?
    private(set) var hasConfirmedRetainedSessionEnd = false
    private let transport: any DocketMCPTransporting
    private let credentials: DocketCredentialStore
    private let oauth: any DocketOAuthAuthorizing
    private let auditLog: AuditLog?
    private var reducer: BrowserWorkSessionReducer
    private var pollingTask: Task<Void, Never>?

    init(
        transport: (any DocketMCPTransporting)? = nil,
        credentials: DocketCredentialStore? = nil,
        oauth: (any DocketOAuthAuthorizing)? = nil,
        docketWebOrigin: URL = DocketServiceEndpoints.current.webOrigin,
        mappings: [WorkDestinationMapping] = [],
        auditLog: AuditLog? = nil
    ) {
        let credentials = credentials ?? DocketCredentialStore()
        self.transport = transport ?? DocketMCPHTTPTransport()
        self.credentials = credentials
        self.oauth = oauth ?? DocketOAuthClient(store: credentials)
        self.auditLog = auditLog
        self.reducer = .init(docketWebOrigin: docketWebOrigin, mappings: mappings)
    }

    var isAuthorized: Bool {
        do {
            return try credentials.load() != nil
        } catch {
            return false
        }
    }

    func policy(at date: Date) -> BrowserPolicySnapshot? {
        reducer.policy(at: date)
    }

    func pollInterval(at date: Date) -> TimeInterval {
        reducer.policy(at: date) == nil && retainedSessionIdentity == nil ? 30 : 5
    }

    func restoreRetainedSessionIdentity(_ identity: BrowserRetainedSessionIdentity) {
        guard reducer.currentSessionID() == nil else { return }
        retainedSessionIdentity = identity
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                await poll(at: now)
                let nanoseconds = UInt64(pollInterval(at: Date()) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func poll(at date: Date) async {
        defer { onPolicyChanged?(reducer.policy(at: date)) }
        do {
            let priorTask = reducer.currentTask()
            let priorSessionID = reducer.currentSessionID()
            let work = try await withAuthorizedAccess(at: date) { accessToken in
                try await self.transport.readActiveWork(accessToken: accessToken)
            }
            lastSuccessfulPoll = date
            lastPollIsHealthy = true
            onAuthenticatedPoll?(date)
            if work.task != nil {
                hasConfirmedPolicyObservation = true
            }
            reducer.observe(work, receivedAt: date)
            updateRetainedSessionIdentity(for: work.task)
            try await reconcileRetainedTask(
                after: work,
                priorTask: priorTask,
                priorSessionID: priorSessionID,
                at: date
            )
        } catch {
            lastPollIsHealthy = false
            reducer.markDocketUnavailable(at: date)
        }
    }

    private func updateRetainedSessionIdentity(for task: DocketActiveWorkTask?) {
        guard let task else { return }
        if task.isTerminal {
            retainedSessionIdentity = nil
            hasConfirmedRetainedSessionEnd = true
        } else if let sessionID = reducer.currentSessionID() {
            retainedSessionIdentity = try? .validated(
                sessionID: sessionID,
                organizationID: task.organizationID,
                taskID: task.id
            )
            hasConfirmedRetainedSessionEnd = false
        }
    }

    private func reconcileRetainedTask(
        after work: DocketActiveWork,
        priorTask: DocketActiveWorkTask?,
        priorSessionID: UUID?,
        at date: Date
    ) async throws {
        guard work.task == nil else { return }
        let identity = retainedSessionIdentity ?? priorTask.flatMap { task in
            guard let priorSessionID else { return nil }
            return try? BrowserRetainedSessionIdentity.validated(
                sessionID: priorSessionID,
                organizationID: task.organizationID,
                taskID: task.id
            )
        }
        guard let identity else { return }
        let state = try await withAuthorizedAccess(at: date) { accessToken in
            try await self.transport.readTaskState(
                organizationID: identity.organizationID,
                taskID: identity.taskID,
                accessToken: accessToken
            )
        }
        guard state.taskID == identity.taskID else {
            throw DocketClientError.invalidResponse
        }
        if state.isTerminal {
            if priorSessionID == identity.sessionID {
                reducer.observeTaskState(
                    sessionID: identity.sessionID,
                    taskID: state.taskID,
                    stateType: state.stateType,
                    archivedAt: state.archivedAt
                )
            }
            retainedSessionIdentity = nil
            hasConfirmedRetainedSessionEnd = true
        } else {
            retainedSessionIdentity = identity
            hasConfirmedRetainedSessionEnd = false
        }
    }

    func connect(at date: Date) async throws {
        let tokens = try await oauth.connect(at: date)
        try credentials.save(tokens)
        await poll(at: date)
    }

    func disconnect(at date: Date) async throws {
        try credentials.clear()
        await transport.resetSession()
        lastPollIsHealthy = false
        reducer.markDocketUnavailable(at: date)
        onPolicyChanged?(reducer.policy(at: date))
    }

    var canBeginBreak: Bool {
        reducer.canBeginBreak
    }

    @discardableResult
    func beginBreak(at date: Date) -> Bool {
        let didBegin = reducer.beginBreak(at: date)
        if didBegin {
            onPolicyChanged?(reducer.policy(at: date))
        }
        return didBegin
    }

    func replaceMappings(_ mappings: [WorkDestinationMapping], at date: Date) {
        reducer.replaceMappings(mappings)
        onPolicyChanged?(reducer.policy(at: date))
    }

    #if DEBUG
        func seedDemo(_ work: DocketActiveWork, at date: Date) {
            reducer.observe(work, receivedAt: date)
            lastSuccessfulPoll = date
            hasConfirmedPolicyObservation = work.task != nil
            onPolicyChanged?(reducer.policy(at: date))
        }
    #endif

    func review(
        rawDestination: String,
        justification: String,
        challengeAnswer: String?,
        at date: Date,
        expectedSessionID: UUID? = nil,
        requestIsFresh: () -> Bool = { true }
    ) async -> DocketDestinationReview {
        defer { onPolicyChanged?(reducer.policy(at: date)) }
        guard let destination = try? NormalizedHTTPDestination(rawDestination),
              let sessionID = reducer.policy(at: date)?.sessionID,
              expectedSessionID == nil || expectedSessionID == sessionID,
              requestIsFresh(),
              let task = reducer.currentTask(),
              reducer.canReview(destination, at: date)
        else { return .deny(reason: "This destination cannot be reviewed now.") }
        let input = DocketDestinationReviewInput(
            organizationID: task.organizationID,
            taskID: task.id,
            destination: .init(origin: destination.origin, path: destination.path),
            justification: justification,
            challengeAnswer: challengeAnswer
        )
        do {
            let result = try await withAuthorizedAccess(at: date) { accessToken in
                try await self.transport.reviewDestination(input, accessToken: accessToken)
            }
            guard reducer.policy(at: date)?.sessionID == sessionID else {
                return .deny(reason: "Work changed while Docket reviewed this destination.")
            }
            guard requestIsFresh() else {
                return .deny(reason: "The destination request expired during review.")
            }
            switch result {
            case .grant(_, let scope):
                guard reducer.grant(scope, for: destination, at: date) else {
                    reducer.deny(destination, at: date)
                    return .deny(reason: "Docket returned an invalid destination scope.")
                }
            case .deny:
                reducer.deny(destination, at: date)
            case .challenge:
                break
            }
            recordAcceptedReview(result, destination: destination, at: date)
            return result
        } catch {
            guard reducer.policy(at: date)?.sessionID == sessionID else {
                return .deny(reason: "Work changed while Docket reviewed this destination.")
            }
            reducer.deny(destination, at: date)
            return .deny(reason: "Docket could not review this destination.")
        }
    }

    private func validAccessToken(at date: Date) async throws -> String {
        if let tokens = try credentials.load(), tokens.expiresAt > date.addingTimeInterval(30) {
            return tokens.accessToken
        }
        return try await oauth.refresh(now: date).accessToken
    }

    private func withAuthorizedAccess<Value>(
        at date: Date,
        operation: (String) async throws -> Value
    ) async throws -> Value {
        let accessToken = try await validAccessToken(at: date)
        do {
            return try await operation(accessToken)
        } catch DocketClientError.unauthorized {
            await transport.resetSession()
            let freshToken = try await oauth.refresh(now: date).accessToken
            return try await operation(freshToken)
        }
    }
}

private extension DocketBrowserPolicyCoordinator {
    func recordAcceptedReview(
        _ result: DocketDestinationReview,
        destination: NormalizedHTTPDestination,
        at date: Date
    ) {
        let decision: String
        let scopeKind: String
        switch result {
        case .grant(_, let scope):
            decision = "grant"
            scopeKind = scope.kind.rawValue
        case .challenge:
            decision = "challenge"
            scopeKind = "none"
        case .deny:
            decision = "deny"
            scopeKind = "none"
        }
        (auditLog ?? AuditLog.shared).emit(
            .browserDestinationReviewed,
            actor: .app,
            detail: [
                "hostname": .string(destination.reviewURL.host ?? ""),
                "decision": .string(decision),
                "scopeKind": .string(scopeKind)
            ],
            at: date
        )
    }
}
