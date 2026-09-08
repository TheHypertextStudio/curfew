@testable import Curfew
import Foundation
import Testing

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct BrowserWorkPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test("A browser destination removes secrets and tracking data before review")
    func destinationNormalizationRemovesPrivateParts() throws {
        let destination = try NormalizedHTTPDestination(
            "HTTPS://alice:secret@Example.COM:443/research/posts?campaign=lvbt#examples"
        )

        #expect(destination.origin == "https://example.com")
        #expect(destination.path == "/research/posts")
        #expect(destination.reviewURL.absoluteString == "https://example.com/research/posts")
    }

    @Test("A browser destination resolves dot segments before review")
    func destinationNormalizationResolvesDotSegments() throws {
        let destination = try NormalizedHTTPDestination(
            "https://Example.COM/campaign/../research/posts"
        )

        #expect(destination.origin == "https://example.com")
        #expect(destination.path == "/research/posts")
    }

    @Test("Only HTTP and HTTPS destinations can enter browser policy")
    func destinationNormalizationRejectsOtherSchemes() {
        #expect(throws: NormalizedHTTPDestination.Error.self) {
            _ = try NormalizedHTTPDestination("file:///Users/willie/strategy.md")
        }
        #expect(throws: NormalizedHTTPDestination.Error.self) {
            _ = try NormalizedHTTPDestination("javascript:alert(1)")
        }
    }

    @Test("Path scopes stop at a path-segment boundary")
    func pathScopeUsesSegmentBoundary() throws {
        let scope = try BrowserDestinationScope.validatedPathPrefix(
            "https://example.com/research"
        )

        #expect(try scope.allows(NormalizedHTTPDestination("https://example.com/research/posts")))
        #expect(try !scope.allows(NormalizedHTTPDestination("https://example.com/researcher")))
        #expect(try !scope.allows(NormalizedHTTPDestination("https://other.example/research")))
    }

    @Test("A root path prefix allows every path on only its exact origin")
    func rootPathPrefixHasOriginWideSemantics() throws {
        let scope = try BrowserDestinationScope.validatedPathPrefix("https://example.com/")

        #expect(try scope.allows(NormalizedHTTPDestination("https://example.com/anything")))
        #expect(try scope.allows(NormalizedHTTPDestination("https://example.com/")))
        #expect(try !scope.allows(NormalizedHTTPDestination("https://other.example/anything")))
    }

    @Test(
        "Scope construction rejects values that are not exact normalized boundaries",
        arguments: [
            "https://alice:secret@example.com/research",
            "https://example.com/research?private=1",
            "https://example.com/research#private",
            "https://example.com:443/research",
            "research",
            ""
        ]
    )
    func pathScopeRejectsUnnormalizedValues(value: String) {
        #expect(throws: BrowserDestinationScope.ValidationError.self) {
            _ = try BrowserDestinationScope.validatedPathPrefix(value)
        }
    }

    @Test(
        "Origin scope construction rejects values that are not exact origins",
        arguments: [
            "https://alice:secret@example.com",
            "https://example.com/research",
            "https://example.com?private=1",
            "https://example.com#private",
            "https://example.com:443",
            "example.com",
            ""
        ]
    )
    func originScopeRejectsUnnormalizedValues(value: String) {
        #expect(throws: BrowserDestinationScope.ValidationError.self) {
            _ = try BrowserDestinationScope.validatedOrigin(value)
        }
    }

    @Test("Scope decoding cannot bypass normalized construction")
    func scopeDecodingRejectsUnnormalizedValues() {
        let data = Data(
            #"{"kind":"origin","origin":"https://example.com:443"}"#.utf8
        )

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(BrowserDestinationScope.self, from: data)
        }
    }

    @Test("A grant cannot cross from the reviewed destination to another origin")
    func crossOriginGrantIsRejected() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let reviewed = try NormalizedHTTPDestination("https://instagram.com/research")
        let scope = try BrowserDestinationScope.validatedOrigin("https://youtube.com")

        let granted = reducer.grant(scope, for: reviewed, at: now)
        #expect(!granted)
        #expect(try !#require(reducer.policy(at: now))
            .allows(NormalizedHTTPDestination("https://youtube.com/watch"), at: now))
    }

    @Test("The initial policy unions matching mappings, task references, and Docket")
    func initialPolicyUsesEveryTaskOwnedSource() throws {
        let mappings = try [
            WorkDestinationMapping(
                id: "task-map",
                selector: .task("task-lvbt"),
                scope: BrowserDestinationScope.validatedOrigin("https://canva.com")
            ),
            WorkDestinationMapping(
                id: "project-map",
                selector: .project("project-lvbt"),
                scope: BrowserDestinationScope.validatedPathPrefix(
                    "https://transitcenter.org/research"
                )
            ),
            WorkDestinationMapping(
                id: "label-map",
                selector: .label("social"),
                scope: BrowserDestinationScope.validatedOrigin("https://instagram.com")
            ),
            WorkDestinationMapping(
                id: "wrong-project",
                selector: .project("project-other"),
                scope: BrowserDestinationScope.validatedOrigin("https://youtube.com")
            )
        ]
        var reducer = try BrowserWorkSessionReducer(
            docketWebOrigin: #require(URL(string: "https://docket.hypertext.studio")),
            mappings: mappings
        )

        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let policy = try #require(reducer.policy(at: now))

        #expect(try policy.allows(
            NormalizedHTTPDestination("https://canva.com/design/1"),
            at: now
        ))
        #expect(try policy.allows(NormalizedHTTPDestination(
            "https://transitcenter.org/research/bus-social"
        ), at: now))
        #expect(try policy.allows(
            NormalizedHTTPDestination("https://instagram.com/lvbt"),
            at: now
        ))
        #expect(try policy
            .allows(NormalizedHTTPDestination("https://docs.google.com/document/d/1"), at: now))
        #expect(try policy
            .allows(NormalizedHTTPDestination("https://docket.hypertext.studio/today"), at: now))
        #expect(try !policy.allows(
            NormalizedHTTPDestination("https://youtube.com/watch?v=1"),
            at: now
        ))
    }

    @Test("Stopping a timer retains the prior task and its policy")
    func idleTrackingRetainsTask() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)

        reducer.observe(
            DocketActiveWork(
                observedAt: now.addingTimeInterval(5),
                tracking: .idle,
                recordID: nil,
                task: nil
            ),
            receivedAt: now.addingTimeInterval(5)
        )

        let policy = try #require(reducer.policy(at: now.addingTimeInterval(5)))
        #expect(policy.task.id == "task-lvbt")
        #expect(policy.tracking == .idle)
    }

    @Test("Switching tasks revokes every grant from the old session")
    func switchingTaskRevokesGrants() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let destination = try NormalizedHTTPDestination("https://transitcenter.org/news")
        let scope = try BrowserDestinationScope.validatedOrigin(destination.origin)
        let granted = reducer.grant(scope, for: destination, at: now)
        #expect(granted)

        reducer.observe(
            activeWork(
                tracking: .running,
                taskID: "task-new",
                observedAt: now.addingTimeInterval(5)
            ),
            receivedAt: now.addingTimeInterval(5)
        )

        let policy = try #require(reducer.policy(at: now.addingTimeInterval(5)))
        #expect(!policy.allows(destination, at: now.addingTimeInterval(5)))
        #expect(policy.task.id == "task-new")
    }

    @Test("A grant expires after thirty minutes even when the session continues")
    func grantExpiresAfterThirtyMinutes() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let destination = try NormalizedHTTPDestination("https://transitcenter.org/news")
        let scope = try BrowserDestinationScope.validatedOrigin(destination.origin)
        let granted = reducer.grant(scope, for: destination, at: now)
        #expect(granted)

        #expect(try #require(reducer.policy(at: now.addingTimeInterval(1799)))
            .allows(destination, at: now.addingTimeInterval(1799)))
        let expiredPolicy = try #require(reducer.policy(at: now.addingTimeInterval(1800)))
        #expect(!expiredPolicy.allows(destination, at: now.addingTimeInterval(1800)))
    }

    @Test("A cached policy evaluates grant and break expiry against the current time")
    func cachedPolicyExpiresTemporaryAccess() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .paused), receivedAt: now)
        let destination = try NormalizedHTTPDestination("https://transitcenter.org/news")
        let scope = try BrowserDestinationScope.validatedOrigin(destination.origin)
        let granted = reducer.grant(scope, for: destination, at: now)
        let beganBreak = reducer.beginBreak(at: now)
        #expect(granted)
        #expect(beganBreak)
        let cached = try #require(reducer.policy(at: now))
        let restored = try JSONDecoder().decode(
            BrowserPolicySnapshot.self,
            from: JSONEncoder().encode(cached)
        )

        #expect(!restored.scopes.contains(scope))
        #expect(restored.grants == [BrowserSessionGrant(
            scope: scope,
            expiresAt: now.addingTimeInterval(30 * 60)
        )])
        #expect(restored.allows(destination, at: now.addingTimeInterval(15 * 60 - 1)))
        #expect(restored.allows(destination, at: now.addingTimeInterval(30 * 60 - 1)))
        #expect(!restored.allows(destination, at: now.addingTimeInterval(30 * 60)))
        let unknown = try NormalizedHTTPDestination("https://youtube.com/watch")
        #expect(restored.allows(unknown, at: now.addingTimeInterval(15 * 60 - 1)))
        #expect(!restored.allows(unknown, at: now.addingTimeInterval(15 * 60)))
    }

    @Test("A denial prevents another review for five minutes")
    func denialCreatesFiveMinuteCooldown() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let destination = try NormalizedHTTPDestination("https://instagram.com/explore")

        reducer.deny(destination, at: now)

        #expect(!reducer.canReview(destination, at: now.addingTimeInterval(299)))
        #expect(reducer.canReview(destination, at: now.addingTimeInterval(300)))
    }

    @Test("A break requires paused or idle tracking and ends after fifteen minutes")
    func breakEligibilityAndExpiry() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let runningBreak = reducer.beginBreak(at: now)
        #expect(!runningBreak)

        reducer.observe(
            activeWork(tracking: .paused, observedAt: now.addingTimeInterval(5)),
            receivedAt: now.addingTimeInterval(5)
        )
        let pausedBreak = reducer.beginBreak(at: now.addingTimeInterval(5))
        #expect(pausedBreak)
        let unknown = try NormalizedHTTPDestination("https://youtube.com/watch")
        #expect(try #require(reducer.policy(at: now.addingTimeInterval(904)))
            .allows(unknown, at: now.addingTimeInterval(904)))
        let expiredBreakPolicy = try #require(reducer.policy(at: now.addingTimeInterval(905)))
        #expect(!expiredBreakPolicy.allows(unknown, at: now.addingTimeInterval(905)))
    }

    @Test("A paused interval cannot renew its fifteen-minute break")
    func breakCannotRenewWithoutResuming() throws {
        var reducer = reducer()
        reducer.observe(
            activeWork(tracking: .paused, observedAt: now.addingTimeInterval(1)),
            receivedAt: now.addingTimeInterval(1)
        )
        let firstBreak = reducer.beginBreak(at: now.addingTimeInterval(1))
        let renewedBreak = reducer.beginBreak(at: now.addingTimeInterval(100))

        #expect(firstBreak)
        #expect(!renewedBreak)
        let unknown = try NormalizedHTTPDestination("https://youtube.com/watch")
        let policy = try #require(reducer.policy(at: now.addingTimeInterval(901)))
        #expect(!policy.allows(unknown, at: now.addingTimeInterval(901)))
    }

    @Test("Resuming tracked work cancels an active break")
    func resumeCancelsBreak() throws {
        var reducer = reducer()
        reducer.observe(
            activeWork(tracking: .paused, observedAt: now.addingTimeInterval(1)),
            receivedAt: now.addingTimeInterval(1)
        )
        let began = reducer.beginBreak(at: now.addingTimeInterval(1))
        #expect(began)

        reducer.observe(
            activeWork(tracking: .running, observedAt: now.addingTimeInterval(5)),
            receivedAt: now.addingTimeInterval(5)
        )

        let unknown = try NormalizedHTTPDestination("https://youtube.com/watch")
        let policy = try #require(reducer.policy(at: now.addingTimeInterval(5)))
        #expect(!policy.allows(unknown, at: now.addingTimeInterval(5)))
    }

    @Test("Paused to idle creates one new break eligibility")
    func pausedToIdleCreatesOneBreakEligibility() {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .paused), receivedAt: now)
        let pausedBreak = reducer.beginBreak(at: now)
        #expect(pausedBreak)

        let idleAt = now.addingTimeInterval(5)
        reducer.observe(
            DocketActiveWork(observedAt: idleAt, tracking: .idle, recordID: nil, task: nil),
            receivedAt: idleAt
        )

        let idleBreak = reducer.beginBreak(at: idleAt)
        #expect(idleBreak)
        reducer.observe(
            DocketActiveWork(
                observedAt: idleAt.addingTimeInterval(1),
                tracking: .idle,
                recordID: nil,
                task: nil
            ),
            receivedAt: idleAt.addingTimeInterval(1)
        )
        let repeatedIdleBreak = reducer.beginBreak(at: idleAt.addingTimeInterval(1))
        #expect(!repeatedIdleBreak)
    }

    @Test("Idle to paused creates one new break eligibility")
    func idleToPausedCreatesOneBreakEligibility() {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .idle), receivedAt: now)
        let idleBreak = reducer.beginBreak(at: now)
        #expect(idleBreak)

        let pausedAt = now.addingTimeInterval(5)
        reducer.observe(
            activeWork(tracking: .paused, observedAt: pausedAt),
            receivedAt: pausedAt
        )

        let pausedBreak = reducer.beginBreak(at: pausedAt)
        #expect(pausedBreak)
        reducer.observe(
            activeWork(tracking: .paused, observedAt: pausedAt.addingTimeInterval(1)),
            receivedAt: pausedAt.addingTimeInterval(1)
        )
        let repeatedPausedBreak = reducer.beginBreak(at: pausedAt.addingTimeInterval(1))
        #expect(!repeatedPausedBreak)
    }

    @Test("A browser policy snapshot serializes only the task identity")
    func snapshotSerializationOmitsDocketTaskContext() throws {
        let task = DocketActiveWorkTask(
            id: "task-lvbt",
            organizationID: "org-lvbt",
            title: "Complete LVBT social strategy",
            description: "Confidential description",
            stateType: "started",
            workspace: .init(id: "workspace-lvbt", name: "Secret workspace"),
            project: .init(id: "project-lvbt", name: "Secret project", summary: "Secret summary"),
            labels: [.init(id: "social", name: "Secret label")],
            references: [.init(
                source: .projectResource,
                title: "Secret reference",
                url: "https://alice:password@example.com/research?token=secret#private"
            )]
        )
        var reducer = reducer()
        reducer.observe(
            DocketActiveWork(
                observedAt: now,
                tracking: .running,
                recordID: "record-1",
                task: task
            ),
            receivedAt: now
        )

        let policy = try #require(reducer.policy(at: now))
        let data = try JSONEncoder().encode(policy)
        let json = try #require(String(bytes: data, encoding: .utf8))

        #expect(json.contains("task-lvbt"))
        #expect(json.contains("Complete LVBT social strategy"))
        #expect(!json.contains("Confidential description"))
        #expect(!json.contains("Secret workspace"))
        #expect(!json.contains("Secret project"))
        #expect(!json.contains("Secret summary"))
        #expect(!json.contains("Secret label"))
        #expect(!json.contains("Secret reference"))
        #expect(!json.contains("alice"))
        #expect(!json.contains("password"))
        #expect(!json.contains("token"))
        #expect(!json.contains("private"))
    }

    @Test(
        "A terminal task ends the retained session",
        arguments: ["completed", "canceled", "archived"]
    )
    func terminalTaskEndsSession(stateType: String) throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let sessionID = try #require(reducer.policy(at: now)?.sessionID)

        reducer.observeTaskState(
            sessionID: sessionID,
            taskID: "task-lvbt",
            stateType: stateType,
            archivedAt: nil
        )

        #expect(reducer.policy(at: now.addingTimeInterval(5)) == nil)
    }

    @Test("An incoming terminal task ends retained work even when its ID differs")
    func differentTerminalTaskEndsSession() {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)

        reducer.observe(
            activeWork(
                tracking: .running,
                taskID: "task-terminal",
                stateType: "completed",
                observedAt: now.addingTimeInterval(5)
            ),
            receivedAt: now.addingTimeInterval(5)
        )

        #expect(reducer.policy(at: now.addingTimeInterval(5)) == nil)
    }

    @Test("An archive timestamp ends a retained session")
    func archiveTimestampEndsSession() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let sessionID = try #require(reducer.policy(at: now)?.sessionID)

        reducer.observeTaskState(
            sessionID: sessionID,
            taskID: "task-lvbt",
            stateType: "started",
            archivedAt: now.addingTimeInterval(5)
        )

        #expect(reducer.policy(at: now.addingTimeInterval(5)) == nil)
    }

    @Test("An older Docket response cannot restore prior work")
    func staleResponseIsIgnored() throws {
        var reducer = reducer()
        reducer.observe(
            activeWork(
                tracking: .running,
                taskID: "task-new",
                observedAt: now.addingTimeInterval(10)
            ),
            receivedAt: now.addingTimeInterval(10)
        )

        reducer.observe(activeWork(tracking: .running), receivedAt: now.addingTimeInterval(11))

        #expect(try #require(reducer.policy(at: now.addingTimeInterval(11))).task.id == "task-new")
    }

    @Test("An outage leaves unknown destinations blocked")
    func unavailableDocketFailsClosed() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        reducer.markDocketUnavailable(at: now.addingTimeInterval(5))

        let policy = try #require(reducer.policy(at: now.addingTimeInterval(5)))
        #expect(policy.connectionIsHealthy == false)
        #expect(try !policy.allows(
            NormalizedHTTPDestination("https://youtube.com/watch"),
            at: now.addingTimeInterval(5)
        ))
        #expect(try policy
            .allows(
                NormalizedHTTPDestination("https://docs.google.com/document/d/1"),
                at: now.addingTimeInterval(5)
            ))
    }

    private func reducer() -> BrowserWorkSessionReducer {
        BrowserWorkSessionReducer(
            docketWebOrigin: URL(string: "https://docket.hypertext.studio")!,
            mappings: []
        )
    }

    private func activeWork(
        tracking: DocketTrackingState,
        taskID: String = "task-lvbt",
        stateType: String = "started",
        observedAt: Date? = nil
    ) -> DocketActiveWork {
        DocketActiveWork(
            observedAt: observedAt ?? now,
            tracking: tracking,
            recordID: "record-1",
            task: DocketActiveWorkTask(
                id: taskID,
                organizationID: "org-lvbt",
                title: "Complete LVBT social strategy",
                description: "Write the channel strategy.",
                stateType: stateType,
                workspace: .init(id: "workspace-lvbt", name: "LVBT"),
                project: .init(
                    id: "project-lvbt",
                    name: "Social strategy",
                    summary: "Plan LVBT social media."
                ),
                labels: [.init(id: "social", name: "Social media")],
                references: [
                    .init(
                        source: .taskAttachment,
                        title: "Strategy document",
                        url: "https://docs.google.com/document/d/1?editing=true"
                    )
                ]
            )
        )
    }
}
