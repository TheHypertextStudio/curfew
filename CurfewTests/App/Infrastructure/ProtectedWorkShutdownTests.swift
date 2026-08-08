@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for the app-side kill path.
///
/// `ShutdownWorkflow.requestGracefulTermination` is the reason a background
/// agent dies at curfew today: terminating a terminal emulator takes every
/// child process with it. These tests pin the three properties that make
/// survival a feature rather than an accident — the allowlist reaches the
/// terminate sweep, a live claim holds the attempt back, and the hold has an
/// end.
@MainActor
struct ProtectedWorkShutdownTests {
    private func fire(
        _ workflow: inout ShutdownWorkflow,
        at now: Date,
        controller: ShutdownControllerSpy,
        policy: ProtectedWorkPolicy = .default,
        hasActiveProtectedWork: Bool = false,
        isBreakGlassActive: Bool = false
    ) {
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: controller,
            isActiveDevice: true,
            protectedWork: policy,
            hasActiveProtectedWork: hasActiveProtectedWork,
            isBreakGlassActive: isBreakGlassActive
        )
    }

    @Test("The allowlist reaches the graceful-terminate sweep")
    func policyReachesTheController() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        var policy = ProtectedWorkPolicy.default
        policy.protectedProcessNames = ["my-agent"]

        fire(&workflow, at: start, controller: controller, policy: policy)
        fire(&workflow, at: start.addingTimeInterval(600), controller: controller, policy: policy)

        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])
        #expect(controller.lastSparedPolicy?.protectedProcessNames == ["my-agent"])
    }

    @Test("A live claim defers the shutdown instead of running it")
    func activeWorkDefersTheShutdown() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()

        fire(&workflow, at: start, controller: controller)
        fire(
            &workflow,
            at: start.addingTimeInterval(600),
            controller: controller,
            hasActiveProtectedWork: true
        )

        guard case .deferred(let until) = workflow.phase else {
            Issue.record("expected deferred phase, got \(workflow.phase)")
            return
        }
        let bound = TimeInterval(ProtectedWorkPolicy.default.maximumDeferralMinutes * 60)
        #expect(until == start.addingTimeInterval(600 + bound))
        #expect(controller.callLog.isEmpty)
    }

    @Test("Deferral is bounded — the shutdown runs once the budget is spent")
    func deferralIsBounded() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        let due = start.addingTimeInterval(600)
        let bound = TimeInterval(ProtectedWorkPolicy.default.maximumDeferralMinutes * 60)

        fire(&workflow, at: start, controller: controller)
        fire(&workflow, at: due, controller: controller, hasActiveProtectedWork: true)
        // Still claiming, well past the bound.
        fire(
            &workflow,
            at: due.addingTimeInterval(bound + 1),
            controller: controller,
            hasActiveProtectedWork: true
        )

        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])
    }

    @Test("Work finishing lets the deferred shutdown proceed on the next tick")
    func finishingWorkResumesTheShutdown() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        let due = start.addingTimeInterval(600)

        fire(&workflow, at: start, controller: controller)
        fire(&workflow, at: due, controller: controller, hasActiveProtectedWork: true)
        fire(&workflow, at: due.addingTimeInterval(60), controller: controller)

        #expect(workflow.phase == .completed)
    }

    @Test("Break-glass holds auto-shutdown down for as long as it is in force")
    func breakGlassReleasesTheWorkflow() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()

        fire(&workflow, at: start, controller: controller)
        for offset in [600.0, 900.0, 1200.0] {
            fire(
                &workflow,
                at: start.addingTimeInterval(offset),
                controller: controller,
                isBreakGlassActive: true
            )
            #expect(workflow.phase == .releasedByBreakGlass)
            #expect(controller.callLog.isEmpty)
        }
    }

    @Test("Revoking the release re-arms the workflow, as it re-arms the daemon")
    func breakGlassRevokeReArmsTheWorkflow() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()

        fire(&workflow, at: start, controller: controller)
        fire(
            &workflow,
            at: start.addingTimeInterval(600),
            controller: controller,
            isBreakGlassActive: true
        )
        #expect(workflow.phase == .releasedByBreakGlass)

        // `curfew-ctl break-glass --revoke` removes the record. The next tick
        // sees no release and must act — the daemon does, and an app that
        // stayed released would leave the two enforcing different rules.
        fire(&workflow, at: start.addingTimeInterval(660), controller: controller)
        #expect(workflow.phase == .completed)
        #expect(controller.callLog == ["graceful", "shutdown"])
    }

    @Test("Revoking hands protected work a full grace window, not a spent one")
    func revokeRestoresTheFullDeferralBudget() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        let due = start.addingTimeInterval(600)
        let bound = TimeInterval(ProtectedWorkPolicy.default.maximumDeferralMinutes * 60)

        fire(&workflow, at: start, controller: controller)
        // Work is live and a release is in force; the release wins and no
        // deferral window opens underneath it.
        fire(
            &workflow,
            at: due,
            controller: controller,
            hasActiveProtectedWork: true,
            isBreakGlassActive: true
        )
        #expect(workflow.phase == .releasedByBreakGlass)

        // Revoked well past what would have been the deferral deadline. Work
        // is still live, so it gets its own budget measured from now.
        let revoked = due.addingTimeInterval(bound + 600)
        fire(&workflow, at: revoked, controller: controller, hasActiveProtectedWork: true)
        #expect(workflow.phase == .deferred(until: revoked.addingTimeInterval(bound)))
        #expect(controller.callLog.isEmpty)
    }

    @Test("Break-glass outranks a protected-work deferral")
    func breakGlassOutranksDeferral() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()

        fire(&workflow, at: start, controller: controller)
        fire(
            &workflow,
            at: start.addingTimeInterval(600),
            controller: controller,
            hasActiveProtectedWork: true,
            isBreakGlassActive: true
        )
        #expect(workflow.phase == .releasedByBreakGlass)
    }

    @Test("Both holds explain themselves on the lockout screen")
    func statusLinesDescribeTheHold() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        let due = start.addingTimeInterval(600)

        fire(&workflow, at: start, controller: controller)
        fire(&workflow, at: due, controller: controller, hasActiveProtectedWork: true)
        let deferredLine = workflow.statusLine(now: due) ?? ""
        #expect(deferredLine.contains("Protected work"))
        #expect(deferredLine.contains("Lockout remains active"))

        var released = ShutdownWorkflow()
        fire(&released, at: start, controller: controller)
        fire(&released, at: due, controller: controller, isBreakGlassActive: true)
        let releasedLine = released.statusLine(now: due) ?? ""
        #expect(releasedLine.contains("Emergency release"))
        #expect(releasedLine.contains("lockout remains active"))
    }

    @Test("Leaving lockout clears the deferral so the next window starts fresh")
    func leavingLockoutResetsTheDeferral() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [true])
        let start = Date()
        let due = start.addingTimeInterval(600)

        fire(&workflow, at: start, controller: controller)
        fire(&workflow, at: due, controller: controller, hasActiveProtectedWork: true)

        workflow.update(
            now: due.addingTimeInterval(60),
            isLocked: false,
            isEnabled: true,
            delayMinutes: 10,
            controller: controller
        )
        #expect(workflow.phase == .idle)

        // A fresh window gets the whole bound back, measured from its own
        // due date rather than from last night's.
        let nextStart = due.addingTimeInterval(3600)
        fire(&workflow, at: nextStart, controller: controller)
        let nextDue = nextStart.addingTimeInterval(600)
        fire(&workflow, at: nextDue, controller: controller, hasActiveProtectedWork: true)
        guard case .deferred(let until) = workflow.phase else {
            Issue.record("expected deferred phase, got \(workflow.phase)")
            return
        }
        let bound = TimeInterval(ProtectedWorkPolicy.default.maximumDeferralMinutes * 60)
        #expect(until == nextDue.addingTimeInterval(bound))
    }
}
