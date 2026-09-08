@testable import Curfew
import Foundation
import Testing

// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
struct DocketBrowserPolicyClientTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test("Docket OAuth asks only for work review and offline access")
    func oauthRequestUsesSeparateDocketScopes() throws {
        let request = try DocketOAuthAuthorizationRequest.create(
            clientID: "registered-client",
            state: "state-value",
            verifier: String(repeating: "v", count: 64),
            endpoints: .production
        )
        let components = try #require(URLComponents(
            url: request.authorizationURL,
            resolvingAgainstBaseURL: false
        ))
        let query = try Dictionary(uniqueKeysWithValues: #require(components.queryItems).map {
            try ($0.name, #require($0.value))
        })

        #expect(components.host == "docket.hypertext.studio")
        #expect(query["resource"] == "https://docket-api.hypertext.studio/mcp")
        #expect(try Set(#require(query["scope"]).split(separator: " ").map(String.init)) == [
            "work:read", "agents:run", "offline_access"
        ])
        #expect(DocketServiceEndpoints.production.keychainService ==
            "studio.hypertext.curfew.docket")
    }

    @Test(
        "OAuth callback rejects duplicate security parameters without trapping",
        arguments: [
            "studio.hypertext.curfew://docket-oauth/callback?state=s&state=s&code=c",
            "studio.hypertext.curfew://docket-oauth/callback?state=s&code=c&code=c",
            "studio.hypertext.curfew://docket-oauth/callback?state=s&code=c&error=e&error=e"
        ]
    )
    func oauthCallbackRejectsDuplicateParameters(value: String) throws {
        let callback = try #require(URL(string: value))

        #expect(throws: DocketClientError.invalidResponse) {
            _ = try DocketOAuthCallback.authorizationCode(from: callback, expectedState: "s")
        }
    }

    @Test("Docket OAuth registers a public client once and reuses its Keychain identifier")
    func oauthRegistrationIsPersistedAndReused() async throws {
        let secrets = MemoryDocketSecretStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        var requestCount = 0
        DocketURLProtocol.handler = { request in
            requestCount += 1
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString ==
                "https://docket-api.hypertext.studio/api/auth/oauth2/register")
            let body = try requestBody(request)
            let object = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(object["token_endpoint_auth_method"] as? String == "none")
            #expect(object["scope"] as? String == "work:read agents:run offline_access")
            #expect(object["redirect_uris"] as? [String] == [
                "studio.hypertext.curfew://docket-oauth/callback"
            ])
            return try (
                HTTPURLResponse(
                    url: #require(request.url),
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"client_id":"issued-client"}"#.utf8)
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let store = DocketCredentialStore(secretStore: secrets)
        let client = DocketOAuthClient(
            store: store,
            session: URLSession(configuration: configuration),
            endpoints: .production
        )

        let first = try await client.makeAuthorizationRequest(
            state: "state-1",
            verifier: String(repeating: "v", count: 64)
        )
        let second = try await client.makeAuthorizationRequest(
            state: "state-2",
            verifier: String(repeating: "w", count: 64)
        )

        #expect(first.clientID == "issued-client")
        #expect(second.clientID == "issued-client")
        #expect(requestCount == 1)
    }

    @Test("Docket refresh rotates both credentials in its own store")
    func oauthRefreshRotatesCredentials() async throws {
        let secrets = MemoryDocketSecretStore()
        try secrets.save(Data("issued-client".utf8), for: DocketCredentialStore.clientIDAccount)
        try secrets.save(Data("old-refresh".utf8), for: DocketCredentialStore.refreshTokenAccount)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            let body = try #require(String(bytes: requestBody(request), encoding: .utf8))
            let items = try #require(URLComponents(string: "?" + body)?.queryItems)
            let fields = Dictionary(uniqueKeysWithValues: items.compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(fields["grant_type"] == "refresh_token")
            #expect(fields["refresh_token"] == "old-refresh")
            #expect(request.url?.absoluteString ==
                "https://docket-api.hypertext.studio/api/auth/oauth2/token")
            return try (
                HTTPURLResponse(
                    url: #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(
                    // swiftlint:disable:next line_length
                    #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":3600}"#
                        .utf8
                )
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let store = DocketCredentialStore(secretStore: secrets)
        let client = DocketOAuthClient(
            store: store,
            session: URLSession(configuration: configuration),
            endpoints: .production
        )

        let tokens = try await client.refresh(now: now)

        #expect(tokens.accessToken == "new-access")
        #expect(try store.load()?.refreshToken == "new-refresh")
        #expect(try store.load()?.expiresAt == now.addingTimeInterval(3600))
    }

    @Test("The HTTP transport sends real MCP initialize, resource, and review calls")
    // swiftlint:disable:next function_body_length
    func httpTransportUsesDocketMCPShapes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        var methods: [String] = []
        DocketURLProtocol.handler = { request in
            let body = try requestBody(request)
            let object = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            methods.append(method)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            let responseURL = try #require(request.url)
            switch method {
            case "initialize":
                let params = try #require(object["params"] as? [String: Any])
                #expect(params["protocolVersion"] as? String == "2025-11-25")
                return try sseResponse(
                    [
                        "jsonrpc": "2.0", "id": object["id"]!,
                        "result": [
                            "protocolVersion": "2025-11-25",
                            "capabilities": [:],
                            "serverInfo": ["name": "Docket", "version": "1"]
                        ]
                    ],
                    url: responseURL,
                    sessionID: "session-1"
                )
            case "notifications/initialized":
                #expect(request.value(forHTTPHeaderField: "Mcp-Session-Id") == "session-1")
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            case "resources/read":
                let params = try #require(object["params"] as? [String: Any])
                #expect(params["uri"] as? String == "docket://hub/active-work")
                // swiftlint:disable:next line_length
                let text = #"{"schemaVersion":"active-work/1","observedAt":"2026-09-08T08:00:00Z","tracking":"idle","recordId":null,"task":null}"#
                let payload: [String: Any] = [
                    "jsonrpc": "2.0", "id": object["id"]!,
                    "result": ["contents": [["uri": "docket://hub/active-work", "text": text]]]
                ]
                return try sseResponse(payload, url: responseURL)
            case "tools/call":
                let params = try #require(object["params"] as? [String: Any])
                #expect(params["name"] as? String == "review_work_destination")
                let arguments = try #require(params["arguments"] as? [String: Any])
                #expect(arguments["organizationId"] as? String == "org-lvbt")
                let payload: [String: Any] = [
                    "jsonrpc": "2.0", "id": object["id"]!,
                    "result": [
                        "content": [[
                            "type": "text",
                            "text": #"{"decision":"deny","reason":"No."}"#
                        ]],
                        "structuredContent": ["decision": "deny", "reason": "No."]
                    ]
                ]
                return try sseResponse(payload, url: responseURL)
            default:
                throw DocketClientError.invalidResponse
            }
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        let work = try await transport.readActiveWork(accessToken: "access")
        let review = try await transport.reviewDestination(.init(
            organizationID: "org-lvbt",
            taskID: "task-lvbt",
            destination: .init(origin: "https://instagram.com", path: "/explore"),
            justification: "I will compare three posts and record the patterns.",
            challengeAnswer: nil
        ), accessToken: "access")

        #expect(work.tracking == .idle)
        #expect(review == .deny(reason: "No."))
        #expect(methods == [
            "initialize", "notifications/initialized", "resources/read", "tools/call"
        ])
    }

    @Test(
        "MCP rejects a missing or duplicate SSE data event",
        arguments: [
            "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n",
            "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n" +
                "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n\n",
            "event: message\ndata: \n\n"
        ]
    )
    func mcpRejectsInvalidSSEDataCardinality(frame: String) async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            try (
                HTTPURLResponse(
                    url: #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "text/event-stream",
                        "Mcp-Session-Id": "session-1"
                    ]
                )!,
                Data(frame.utf8)
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        await #expect(throws: DocketClientError.self) {
            _ = try await transport.readActiveWork(accessToken: "access")
        }
    }

    @Test("MCP rejects a JSON-RPC response for another request")
    func mcpRejectsMismatchedResponseID() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            try sseResponse(
                ["jsonrpc": "2.0", "id": 999, "result": [:]],
                url: #require(request.url),
                sessionID: "session-1"
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        await #expect(throws: DocketClientError.self) {
            _ = try await transport.readActiveWork(accessToken: "access")
        }
    }

    @Test("An archived task resource is terminal even when its state type is active")
    func taskResourceDecodesArchivedAt() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            let object = try #require(
                JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            let responseURL = try #require(request.url)
            if method == "notifications/initialized" {
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            if method == "initialize" {
                return try sseResponse(
                    ["jsonrpc": "2.0", "id": object["id"]!, "result": [:]],
                    url: responseURL,
                    sessionID: "session-1"
                )
            }
            let text =
                #"{"id":"task-lvbt","stateType":"started","archivedAt":"2026-09-08T09:00:00Z"}"#
            return try sseResponse(
                [
                    "jsonrpc": "2.0", "id": object["id"]!,
                    "result": ["contents": [[
                        "uri": "docket://org-lvbt/task/task-lvbt", "text": text
                    ]]]
                ],
                url: responseURL
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        let state = try await transport.readTaskState(
            organizationID: "org-lvbt",
            taskID: "task-lvbt",
            accessToken: "access"
        )

        #expect(state.archivedAt != nil)
        #expect(state.isTerminal)
    }

    @Test("OAuth registration rejects a response larger than 32 KiB")
    func oauthRegistrationRejectsOversizedResponse() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            let padding = String(repeating: "x", count: 33 * 1024)
            let data = try JSONSerialization.data(withJSONObject: [
                "client_id": "issued-client", "padding": padding
            ])
            return try jsonResponse([:], url: #require(request.url), data: data)
        }
        defer { DocketURLProtocol.handler = nil }
        let client = DocketOAuthClient(
            store: DocketCredentialStore(secretStore: MemoryDocketSecretStore()),
            session: URLSession(configuration: configuration),
            endpoints: .production
        )

        await #expect(throws: DocketClientError.self) {
            _ = try await client.registerClientIfNeeded()
        }
    }

    @Test("OAuth token exchange rejects a response larger than 32 KiB")
    func oauthTokenExchangeRejectsOversizedResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            let padding = String(repeating: "x", count: 33 * 1024)
            let data = try JSONSerialization.data(withJSONObject: [
                "access_token": "access",
                "refresh_token": "refresh",
                "token_type": "Bearer",
                "expires_in": 3600,
                "padding": padding
            ])
            return try jsonResponse([:], url: #require(request.url), data: data)
        }
        defer { DocketURLProtocol.handler = nil }
        let client = DocketOAuthClient(
            store: DocketCredentialStore(secretStore: MemoryDocketSecretStore()),
            session: URLSession(configuration: configuration),
            endpoints: .production
        )
        let request = try DocketOAuthAuthorizationRequest.create(
            clientID: "issued-client",
            state: "state",
            verifier: String(repeating: "v", count: 64),
            endpoints: .production
        )

        await #expect(throws: DocketClientError.self) {
            _ = try await client.exchange(code: "code", request: request, now: now)
        }
    }

    @Test("MCP rejects a response larger than its one MiB wire limit")
    func mcpRejectsOversizedResponse() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        DocketURLProtocol.handler = { request in
            let padding = String(repeating: "x", count: 1_048_576)
            return try sseResponse(
                ["jsonrpc": "2.0", "id": 1, "result": ["padding": padding]],
                url: #require(request.url),
                sessionID: "session-1"
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        await #expect(throws: DocketClientError.self) {
            _ = try await transport.readActiveWork(accessToken: "access")
        }
    }

    @Test("MCP resets a rejected session and reinitializes once")
    // swiftlint:disable:next function_body_length
    func mcpReinitializesAfterOneDeadSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        var methods: [String] = []
        var initializationCount = 0
        var resourceCount = 0
        DocketURLProtocol.handler = { request in
            let object = try #require(
                JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            methods.append(method)
            let responseURL = try #require(request.url)
            switch method {
            case "initialize":
                initializationCount += 1
                return try sseResponse(
                    ["jsonrpc": "2.0", "id": object["id"]!, "result": [:]],
                    url: responseURL,
                    sessionID: "session-\(initializationCount)"
                )
            case "notifications/initialized":
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            case "resources/read":
                resourceCount += 1
                if resourceCount == 1 {
                    return (
                        HTTPURLResponse(
                            url: responseURL,
                            statusCode: 404,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        Data()
                    )
                }
                return try activeWorkSseResponse(
                    id: #require(object["id"]),
                    url: responseURL
                )
            default:
                throw DocketClientError.invalidResponse
            }
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        let work = try await transport.readActiveWork(accessToken: "access")

        #expect(work.task?.id == "task-lvbt")
        #expect(methods == [
            "initialize", "notifications/initialized", "resources/read",
            "initialize", "notifications/initialized", "resources/read"
        ])
    }

    @Test("MCP stops after one dead-session retry")
    func mcpDoesNotLoopOnSecondDeadSession() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        var initializationCount = 0
        var resourceCount = 0
        DocketURLProtocol.handler = { request in
            let object = try #require(
                JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            let responseURL = try #require(request.url)
            if method == "initialize" {
                initializationCount += 1
                return try sseResponse(
                    ["jsonrpc": "2.0", "id": object["id"]!, "result": [:]],
                    url: responseURL,
                    sessionID: "session-\(initializationCount)"
                )
            }
            if method == "notifications/initialized" {
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            resourceCount += 1
            return (
                HTTPURLResponse(
                    url: responseURL,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let transport = DocketMCPHTTPTransport(
            endpoint: DocketServiceEndpoints.production.mcpResource,
            session: URLSession(configuration: configuration)
        )

        await #expect(throws: DocketClientError.staleSession) {
            _ = try await transport.readActiveWork(accessToken: "access")
        }
        #expect(initializationCount == 2)
        #expect(resourceCount == 2)
    }

    @Test("A 401 resets MCP, refreshes OAuth, and retries once")
    // swiftlint:disable:next function_body_length
    func coordinatorRefreshesAfterUnauthorized() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        let secrets = MemoryDocketSecretStore()
        try secrets.save(Data("issued-client".utf8), for: DocketCredentialStore.clientIDAccount)
        let store = DocketCredentialStore(secretStore: secrets)
        try store.save(.init(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(3600)
        ))
        var sequence: [String] = []
        var initializationCount = 0
        var resourceCount = 0
        DocketURLProtocol.handler = { request in
            let responseURL = try #require(request.url)
            if responseURL == DocketServiceEndpoints.production.tokenEndpoint {
                sequence.append("token")
                return try jsonResponse([
                    "access_token": "fresh-access",
                    "refresh_token": "fresh-refresh",
                    "token_type": "Bearer",
                    "expires_in": 3600
                ], url: responseURL)
            }
            let object = try #require(
                JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            let token = request.value(forHTTPHeaderField: "Authorization") ?? "missing"
            sequence.append("\(method):\(token)")
            if method == "initialize" {
                initializationCount += 1
                return try sseResponse(
                    ["jsonrpc": "2.0", "id": object["id"]!, "result": [:]],
                    url: responseURL,
                    sessionID: "session-\(initializationCount)"
                )
            }
            if method == "notifications/initialized" {
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            resourceCount += 1
            if resourceCount == 1 {
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            return try activeWorkSseResponse(id: #require(object["id"]), url: responseURL)
        }
        defer { DocketURLProtocol.handler = nil }
        let session = URLSession(configuration: configuration)
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: DocketMCPHTTPTransport(
                endpoint: DocketServiceEndpoints.production.mcpResource,
                session: session
            ),
            credentials: store,
            oauth: DocketOAuthClient(store: store, session: session, endpoints: .production),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)

        #expect(coordinator.policy(at: now)?.task.id == "task-lvbt")
        #expect(sequence == [
            "initialize:Bearer old-access",
            "notifications/initialized:Bearer old-access",
            "resources/read:Bearer old-access",
            "token",
            "initialize:Bearer fresh-access",
            "notifications/initialized:Bearer fresh-access",
            "resources/read:Bearer fresh-access"
        ])
    }

    @Test("A second 401 fails closed without another refresh")
    // swiftlint:disable:next function_body_length
    func coordinatorDoesNotLoopOnSecondUnauthorized() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        let secrets = MemoryDocketSecretStore()
        try secrets.save(Data("issued-client".utf8), for: DocketCredentialStore.clientIDAccount)
        let store = DocketCredentialStore(secretStore: secrets)
        try store.save(.init(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(3600)
        ))
        var refreshCount = 0
        var resourceCount = 0
        var initializationCount = 0
        DocketURLProtocol.handler = { request in
            let responseURL = try #require(request.url)
            if responseURL == DocketServiceEndpoints.production.tokenEndpoint {
                refreshCount += 1
                return try jsonResponse([
                    "access_token": "fresh-access",
                    "refresh_token": "fresh-refresh",
                    "token_type": "Bearer",
                    "expires_in": 3600
                ], url: responseURL)
            }
            let object = try #require(
                JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any]
            )
            let method = try #require(object["method"] as? String)
            if method == "initialize" {
                initializationCount += 1
                return try sseResponse(
                    ["jsonrpc": "2.0", "id": object["id"]!, "result": [:]],
                    url: responseURL,
                    sessionID: "session-\(initializationCount)"
                )
            }
            if method == "notifications/initialized" {
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 202,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }
            resourceCount += 1
            return (
                HTTPURLResponse(
                    url: responseURL,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        defer { DocketURLProtocol.handler = nil }
        let session = URLSession(configuration: configuration)
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: DocketMCPHTTPTransport(
                endpoint: DocketServiceEndpoints.production.mcpResource,
                session: session
            ),
            credentials: store,
            oauth: DocketOAuthClient(store: store, session: session, endpoints: .production),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)

        #expect(coordinator.policy(at: now) == nil)
        #expect(refreshCount == 1)
        #expect(resourceCount == 2)
        #expect(initializationCount == 2)
    }

    @Test("The MCP decoder reads the exact active-work version")
    func activeWorkDecodingUsesPublicContract() throws {
        let data = Data(
            // swiftlint:disable:next line_length
            #"{"schemaVersion":"active-work/1","observedAt":"2026-09-08T08:00:00Z","tracking":"paused","recordId":"record-1","task":{"id":"task-lvbt","organizationId":"org-lvbt","title":"Complete LVBT social strategy","description":null,"stateType":"started","workspace":{"id":"workspace-lvbt","name":"LVBT"},"project":{"id":"project-lvbt","name":"Social strategy","summary":null},"labels":[{"id":"social","name":"Social"}],"references":[{"source":"project_resource","title":"Strategy","url":"https://docs.google.com/document/d/1"}]}}"#
                .utf8
        )

        let work = try DocketMCPWire.decodeActiveWork(data)

        #expect(work.schemaVersion == "active-work/1")
        #expect(work.tracking == .paused)
        #expect(work.recordID == "record-1")
        #expect(work.task?.organizationID == "org-lvbt")
        #expect(work.task?.references.first?.source == .projectResource)
    }

    @Test("The coordinator polls every five seconds while a retained session exists")
    func pollCadenceTracksRetainedSession() async throws {
        let transport = RecordingDocketTransport(activeWork: [activeWork(.running), idleWork()])
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        #expect(coordinator.pollInterval(at: now) == 30)
        await coordinator.poll(at: now)
        #expect(coordinator.pollInterval(at: now) == 5)
        await coordinator.poll(at: now.addingTimeInterval(5))
        #expect(coordinator.pollInterval(at: now.addingTimeInterval(5)) == 5)
    }

    @Test("An idle observation checks the retained task and ends a terminal session")
    func idleObservationChecksTerminalTask() async throws {
        let transport = RecordingDocketTransport(
            activeWork: [activeWork(.running), idleWork()],
            taskStates: [.init(
                taskID: "task-lvbt",
                stateType: "completed",
                observedAt: now.addingTimeInterval(6)
            )]
        )
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)
        await coordinator.poll(at: now.addingTimeInterval(5))

        #expect(coordinator.policy(at: now.addingTimeInterval(6)) == nil)
        #expect(await transport.taskReadCount == 1)
    }

    @Test("An idle observation ends a retained task that has an archive timestamp")
    func idleObservationChecksArchivedTask() async throws {
        let transport = RecordingDocketTransport(
            activeWork: [activeWork(.running), idleWork()],
            taskStates: [.init(
                taskID: "task-lvbt",
                stateType: "started",
                archivedAt: now.addingTimeInterval(5),
                observedAt: now.addingTimeInterval(5)
            )]
        )
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)
        await coordinator.poll(at: now.addingTimeInterval(5))

        #expect(coordinator.policy(at: now.addingTimeInterval(5)) == nil)
    }

    @Test("A late active-work response cannot switch the coordinator backward")
    func coordinatorRejectsStaleResponse() async throws {
        let transport = RecordingDocketTransport(activeWork: [
            activeWork(.running, taskID: "task-new", observedAt: now.addingTimeInterval(10)),
            activeWork(.running, taskID: "task-old", observedAt: now)
        ])
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now.addingTimeInterval(10))
        await coordinator.poll(at: now.addingTimeInterval(11))

        #expect(coordinator.policy(at: now.addingTimeInterval(11))?.task.id == "task-new")
    }

    @Test(
        "A task switch invalidates every in-flight destination review result",
        arguments: ["grant", "challenge", "deny"]
    )
    func taskSwitchInvalidatesReviewResult(kind: String) async throws {
        let staleResult: DocketDestinationReview = switch kind {
        case "grant": try .grant(
                reason: "Allowed.",
                scope: BrowserDestinationScope.validatedOrigin("https://instagram.com")
            )
        case "challenge": .challenge(reason: "More detail.", question: "What will you record?")
        default: .deny(reason: "No.")
        }
        let transport = SuspendedReviewDocketTransport(activeWork: [
            activeWork(.running),
            activeWork(.running, taskID: "task-new", observedAt: now.addingTimeInterval(5))
        ])
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )
        await coordinator.poll(at: now)
        let reviewTask = Task {
            await coordinator.review(
                rawDestination: "https://instagram.com/research",
                justification: "I will record three patterns.",
                challengeAnswer: nil,
                at: now
            )
        }
        await transport.waitUntilReviewStarts()

        await coordinator.poll(at: now.addingTimeInterval(5))
        await transport.resolveFirstReview(with: staleResult)
        let result = await reviewTask.value

        #expect(result == .deny(reason: "Work changed while Docket reviewed this destination."))
        let destination = try NormalizedHTTPDestination("https://instagram.com/research")
        #expect(coordinator.policy(at: now.addingTimeInterval(5))?.allows(destination) == false)
        let second = await coordinator.review(
            rawDestination: "https://instagram.com/research",
            justification: "I will record three patterns.",
            challengeAnswer: nil,
            at: now.addingTimeInterval(5)
        )
        #expect(second == .challenge(reason: "Fresh review.", question: "Name the output."))
        #expect(await transport.reviewCount == 2)
    }

    @Test("An idle task-resource failure retains a fail-closed unhealthy session")
    func missingTaskResourceFailsClosed() async throws {
        let transport = RecordingDocketTransport(activeWork: [activeWork(.running), idleWork()])
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)
        await coordinator.poll(at: now.addingTimeInterval(5))

        let policy = try #require(coordinator.policy(at: now.addingTimeInterval(5)))
        #expect(policy.task.id == "task-lvbt")
        #expect(!policy.connectionIsHealthy)
        #expect(try !policy.allows(NormalizedHTTPDestination("https://youtube.com/watch")))
    }

    @Test("An unauthorized task resource remains fail closed after one token retry")
    func unauthorizedTaskResourceFailsClosed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DocketURLProtocol.self]
        let secrets = MemoryDocketSecretStore()
        try secrets.save(Data("issued-client".utf8), for: DocketCredentialStore.clientIDAccount)
        let store = DocketCredentialStore(secretStore: secrets)
        try store.save(.init(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(3600)
        ))
        var refreshCount = 0
        DocketURLProtocol.handler = { request in
            refreshCount += 1
            return try jsonResponse([
                "access_token": "fresh-access",
                "refresh_token": "fresh-refresh",
                "token_type": "Bearer",
                "expires_in": 3600
            ], url: #require(request.url))
        }
        defer { DocketURLProtocol.handler = nil }
        let session = URLSession(configuration: configuration)
        let transport = RecordingDocketTransport(
            activeWork: [activeWork(.running), idleWork()],
            taskStateError: DocketClientError.unauthorized
        )
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: store,
            oauth: DocketOAuthClient(store: store, session: session, endpoints: .production),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )

        await coordinator.poll(at: now)
        await coordinator.poll(at: now.addingTimeInterval(5))

        let policy = try #require(coordinator.policy(at: now.addingTimeInterval(5)))
        #expect(policy.task.id == "task-lvbt")
        #expect(!policy.connectionIsHealthy)
        #expect(refreshCount == 1)
        #expect(await transport.taskReadCount == 2)
        #expect(try !policy.allows(NormalizedHTTPDestination("https://youtube.com/watch")))
    }

    @Test("Review sends only the normalized origin and path")
    func destinationReviewUsesNormalizedPayload() async throws {
        let transport = try RecordingDocketTransport(
            activeWork: [activeWork(.running)],
            reviews: [.grant(
                reason: "Specific research supports the plan.",
                scope: BrowserDestinationScope.validatedOrigin("https://instagram.com")
            )]
        )
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )
        await coordinator.poll(at: now)

        let result = await coordinator.review(
            rawDestination: "https://alice:secret@Instagram.COM:443/transitcenter?feed=1#post",
            justification: "I will compare three posts and record patterns in the strategy.",
            challengeAnswer: nil,
            at: now
        )

        #expect(result.isGrant)
        let input = try #require(await transport.lastReview)
        #expect(input.destination.origin == "https://instagram.com")
        #expect(input.destination.path == "/transitcenter")
    }

    @Test("Athena failure leaves the destination blocked and starts no grant")
    func reviewFailureFailsClosed() async throws {
        let transport = RecordingDocketTransport(
            activeWork: [activeWork(.running)],
            reviewError: DocketClientError.unavailable
        )
        let coordinator = try DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: fixedCredentials(),
            docketWebOrigin: DocketServiceEndpoints.production.webOrigin
        )
        await coordinator.poll(at: now)

        let result = await coordinator.review(
            rawDestination: "https://instagram.com/explore",
            justification: "I will compare three posts and record patterns in the strategy.",
            challengeAnswer: nil,
            at: now
        )

        #expect(result == .deny(reason: "Docket could not review this destination."))
        let destination = try NormalizedHTTPDestination("https://instagram.com/explore")
        #expect(coordinator.policy(at: now)?.allows(destination) == false)
    }

    private func fixedCredentials() throws -> DocketCredentialStore {
        let secrets = MemoryDocketSecretStore()
        let store = DocketCredentialStore(secretStore: secrets)
        try store.save(.init(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(3600)
        ))
        return store
    }

    private func activeWork(
        _ tracking: DocketTrackingState,
        taskID: String = "task-lvbt",
        observedAt: Date? = nil
    ) -> DocketActiveWork {
        .init(
            observedAt: observedAt ?? now,
            tracking: tracking,
            recordID: "record-1",
            task: .init(
                id: taskID,
                organizationID: "org-lvbt",
                title: "Complete LVBT social strategy",
                description: nil,
                stateType: "started",
                workspace: .init(id: "workspace-lvbt", name: "LVBT"),
                project: nil,
                labels: [],
                references: []
            )
        )
    }

    private func idleWork() -> DocketActiveWork {
        .init(
            observedAt: now.addingTimeInterval(5),
            tracking: .idle,
            recordID: nil,
            task: nil
        )
    }
}

private func jsonResponse(
    _ object: [String: Any],
    url: URL,
    data: Data? = nil
) throws -> (HTTPURLResponse, Data) {
    try (
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!,
        data ?? JSONSerialization.data(withJSONObject: object)
    )
}

private func sseResponse(
    _ object: [String: Any],
    url: URL,
    sessionID: String? = nil
) throws -> (HTTPURLResponse, Data) {
    let payload = try JSONSerialization.data(withJSONObject: object)
    let json = try #require(String(data: payload, encoding: .utf8))
    var headers = ["Content-Type": "text/event-stream"]
    headers["Mcp-Session-Id"] = sessionID
    return (
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        )!,
        Data("event: message\ndata: \(json)\n\n".utf8)
    )
}

private func activeWorkSseResponse(
    id: Any,
    url: URL
) throws -> (HTTPURLResponse, Data) {
    let text = #"""
    {
      "schemaVersion": "active-work/1",
      "observedAt": "2026-09-08T08:00:00Z",
      "tracking": "running",
      "recordId": "record-1",
      "task": {
        "id": "task-lvbt",
        "organizationId": "org-lvbt",
        "title": "Complete LVBT social strategy",
        "description": null,
        "stateType": "started",
        "workspace": { "id": "workspace-lvbt", "name": "LVBT" },
        "project": null,
        "labels": [],
        "references": []
      }
    }
    """#
    return try sseResponse(
        [
            "jsonrpc": "2.0", "id": id,
            "result": ["contents": [["uri": "docket://hub/active-work", "text": text]]]
        ],
        url: url
    )
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    var data = Data()
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 4096)
        if count < 0 {
            throw stream.streamError ?? DocketClientError.invalidResponse
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data
}

private final class MemoryDocketSecretStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values[account] = nil
    }
}

private final class DocketURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor RecordingDocketTransport: DocketMCPTransporting {
    private var activeWorkQueue: [DocketActiveWork]
    private var taskStateQueue: [DocketTaskStateObservation]
    private var reviewQueue: [DocketDestinationReview]
    private let reviewError: Error?
    private let taskStateError: Error?
    private(set) var taskReadCount = 0
    private(set) var lastReview: DocketDestinationReviewInput?

    init(
        activeWork: [DocketActiveWork],
        taskStates: [DocketTaskStateObservation] = [],
        reviews: [DocketDestinationReview] = [],
        reviewError: Error? = nil,
        taskStateError: Error? = nil
    ) {
        self.activeWorkQueue = activeWork
        self.taskStateQueue = taskStates
        self.reviewQueue = reviews
        self.reviewError = reviewError
        self.taskStateError = taskStateError
    }

    func readActiveWork(accessToken _: String) async throws -> DocketActiveWork {
        guard !activeWorkQueue.isEmpty else { throw DocketClientError.unavailable }
        return activeWorkQueue.removeFirst()
    }

    func readTaskState(
        organizationID _: String,
        taskID _: String,
        accessToken _: String
    ) async throws -> DocketTaskStateObservation {
        taskReadCount += 1
        if let taskStateError {
            throw taskStateError
        }
        guard !taskStateQueue.isEmpty else { throw DocketClientError.unavailable }
        return taskStateQueue.removeFirst()
    }

    func reviewDestination(
        _ input: DocketDestinationReviewInput,
        accessToken _: String
    ) async throws -> DocketDestinationReview {
        lastReview = input
        if let reviewError {
            throw reviewError
        }
        guard !reviewQueue.isEmpty else { throw DocketClientError.unavailable }
        return reviewQueue.removeFirst()
    }
}

private actor SuspendedReviewDocketTransport: DocketMCPTransporting {
    private var activeWorkQueue: [DocketActiveWork]
    private var firstReviewContinuation: CheckedContinuation<DocketDestinationReview, Never>?
    private(set) var reviewCount = 0

    init(activeWork: [DocketActiveWork]) {
        self.activeWorkQueue = activeWork
    }

    func readActiveWork(accessToken _: String) async throws -> DocketActiveWork {
        guard !activeWorkQueue.isEmpty else { throw DocketClientError.unavailable }
        return activeWorkQueue.removeFirst()
    }

    func readTaskState(
        organizationID _: String,
        taskID _: String,
        accessToken _: String
    ) async throws -> DocketTaskStateObservation {
        throw DocketClientError.unavailable
    }

    func reviewDestination(
        _ input: DocketDestinationReviewInput,
        accessToken _: String
    ) async throws -> DocketDestinationReview {
        reviewCount += 1
        if reviewCount > 1 {
            return .challenge(reason: "Fresh review.", question: "Name the output.")
        }
        return await withCheckedContinuation { continuation in
            firstReviewContinuation = continuation
        }
    }

    func waitUntilReviewStarts() async {
        while firstReviewContinuation == nil {
            await Task.yield()
        }
    }

    func resolveFirstReview(with result: DocketDestinationReview) {
        firstReviewContinuation?.resume(returning: result)
        firstReviewContinuation = nil
    }
}
