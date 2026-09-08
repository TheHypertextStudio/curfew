@testable import Curfew
import Foundation
import Testing

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
        let scope = BrowserDestinationScope.pathPrefix(
            origin: "https://example.com",
            path: "/research"
        )

        #expect(try scope.allows(NormalizedHTTPDestination("https://example.com/research/posts")))
        #expect(try !scope.allows(NormalizedHTTPDestination("https://example.com/researcher")))
        #expect(try !scope.allows(NormalizedHTTPDestination("https://other.example/research")))
    }

    @Test("The initial policy unions matching mappings, task references, and Docket")
    func initialPolicyUsesEveryTaskOwnedSource() throws {
        let mappings = [
            WorkDestinationMapping(
                id: "task-map",
                selector: .task("task-lvbt"),
                scope: .origin("https://canva.com")
            ),
            WorkDestinationMapping(
                id: "project-map",
                selector: .project("project-lvbt"),
                scope: .pathPrefix(origin: "https://transitcenter.org", path: "/research")
            ),
            WorkDestinationMapping(
                id: "label-map",
                selector: .label("social"),
                scope: .origin("https://instagram.com")
            ),
            WorkDestinationMapping(
                id: "wrong-project",
                selector: .project("project-other"),
                scope: .origin("https://youtube.com")
            )
        ]
        var reducer = try BrowserWorkSessionReducer(
            docketWebOrigin: #require(URL(string: "https://docket.hypertext.studio")),
            mappings: mappings
        )

        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let policy = try #require(reducer.policy(at: now))

        #expect(try policy.allows(NormalizedHTTPDestination("https://canva.com/design/1")))
        #expect(try policy.allows(NormalizedHTTPDestination(
            "https://transitcenter.org/research/bus-social"
        )))
        #expect(try policy.allows(NormalizedHTTPDestination("https://instagram.com/lvbt")))
        #expect(try policy
            .allows(NormalizedHTTPDestination("https://docs.google.com/document/d/1")))
        #expect(try policy
            .allows(NormalizedHTTPDestination("https://docket.hypertext.studio/today")))
        #expect(try !policy.allows(NormalizedHTTPDestination("https://youtube.com/watch?v=1")))
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
        let granted = reducer.grant(.origin(destination.origin), for: destination, at: now)
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
        #expect(!policy.allows(destination))
        #expect(policy.task.id == "task-new")
    }

    @Test("A grant expires after thirty minutes even when the session continues")
    func grantExpiresAfterThirtyMinutes() throws {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)
        let destination = try NormalizedHTTPDestination("https://transitcenter.org/news")
        let granted = reducer.grant(.origin(destination.origin), for: destination, at: now)
        #expect(granted)

        #expect(try #require(reducer.policy(at: now.addingTimeInterval(1799))).allows(destination))
        let expiredPolicy = try #require(reducer.policy(at: now.addingTimeInterval(1800)))
        #expect(!expiredPolicy.allows(destination))
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
        #expect(try #require(reducer.policy(at: now.addingTimeInterval(904))).allows(unknown))
        let expiredBreakPolicy = try #require(reducer.policy(at: now.addingTimeInterval(905)))
        #expect(!expiredBreakPolicy.allows(unknown))
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
        #expect(!policy.allows(unknown))
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
        #expect(!policy.allows(unknown))
    }

    @Test(
        "A terminal task ends the retained session",
        arguments: ["completed", "canceled", "archived"]
    )
    func terminalTaskEndsSession(stateType: String) {
        var reducer = reducer()
        reducer.observe(activeWork(tracking: .running), receivedAt: now)

        reducer.observeTaskState(
            taskID: "task-lvbt",
            stateType: stateType,
            observedAt: now.addingTimeInterval(5)
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
        #expect(try !policy.allows(NormalizedHTTPDestination("https://youtube.com/watch")))
        #expect(try policy
            .allows(NormalizedHTTPDestination("https://docs.google.com/document/d/1")))
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
                stateType: "started",
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
