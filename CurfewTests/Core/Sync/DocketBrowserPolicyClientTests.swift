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
                return (
                    HTTPURLResponse(
                        url: responseURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "application/json",
                            "Mcp-Session-Id": "session-1"
                        ]
                    )!,
                    Data(
                        // swiftlint:disable:next line_length
                        #"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{},"serverInfo":{"name":"Docket","version":"1"}}}"#
                            .utf8
                    )
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
                return try jsonResponse(payload, url: responseURL)
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
                return try jsonResponse(payload, url: responseURL)
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

    @Test("Review sends only the normalized origin and path")
    func destinationReviewUsesNormalizedPayload() async throws {
        let transport = RecordingDocketTransport(
            activeWork: [activeWork(.running)],
            reviews: [.grant(reason: "Specific research supports the plan.", scope: .origin(
                "https://instagram.com"
            ))]
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
    url: URL
) throws -> (HTTPURLResponse, Data) {
    try (
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!,
        JSONSerialization.data(withJSONObject: object)
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
    private(set) var taskReadCount = 0
    private(set) var lastReview: DocketDestinationReviewInput?

    init(
        activeWork: [DocketActiveWork],
        taskStates: [DocketTaskStateObservation] = [],
        reviews: [DocketDestinationReview] = [],
        reviewError: Error? = nil
    ) {
        self.activeWorkQueue = activeWork
        self.taskStateQueue = taskStates
        self.reviewQueue = reviews
        self.reviewError = reviewError
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
