@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// Regression: the shutdown workflow's `isActiveDevice` input changes
/// the grace delay. Active devices follow the user's configured delay;
/// idle devices use a 2-minute default so untended Macs shut down
/// sooner rather than waiting through a human-sized save window.
@MainActor
struct ActiveDeviceShutdownTests {
    @Test("Active device schedules first attempt at configured delay")
    func activeDeviceUsesConfiguredDelay() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [])
        let now = Date()
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: controller,
            isActiveDevice: true
        )
        guard case .scheduled(let date) = workflow.phase else {
            Issue.record("expected scheduled phase, got \(workflow.phase)")
            return
        }
        let delay = Int(date.timeIntervalSince(now))
        #expect(delay == 10 * 60)
    }

    @Test("Idle device schedules first attempt at 2-minute baseline")
    func idleDeviceUsesShortenedDelay() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [])
        let now = Date()
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: controller,
            isActiveDevice: false
        )
        guard case .scheduled(let date) = workflow.phase else {
            Issue.record("expected scheduled phase, got \(workflow.phase)")
            return
        }
        let delay = Int(date.timeIntervalSince(now))
        #expect(delay == 2 * 60)
    }

    @Test("Back-compat default treats caller as active device")
    func defaultCallerIsActive() {
        var workflow = ShutdownWorkflow()
        let controller = ShutdownControllerSpy(results: [])
        let now = Date()
        // Legacy callers that don't pass isActiveDevice — defaulted true.
        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 7,
            controller: controller
        )
        guard case .scheduled(let date) = workflow.phase else {
            Issue.record("expected scheduled phase")
            return
        }
        let delay = Int(date.timeIntervalSince(now))
        #expect(delay == 7 * 60)
    }
}
