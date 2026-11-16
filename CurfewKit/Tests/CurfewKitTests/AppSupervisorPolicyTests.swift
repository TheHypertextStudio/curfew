import CurfewKit
import Foundation
import Testing

struct AppSupervisorPolicyTests {
    @Test("Moving the clock backward preserves only the remaining restart delay")
    func backwardClockDoesNotStrandRecovery() {
        var policy = AppSupervisorPolicy()
        let now = Date(timeIntervalSince1970: 10000)
        let clockDecision1 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(clockDecision1)
        policy.launchCompleted(at: now)
        let clockDecision2 = policy.shouldLaunch(at: now.addingTimeInterval(2), appIsRunning: false)
        #expect(!clockDecision2)

        let corrected = now.addingTimeInterval(-3600)
        let clockDecision3 = policy.shouldLaunch(at: corrected, appIsRunning: false)
        #expect(!clockDecision3)
        let clockDecision4 = policy.shouldLaunch(
            at: corrected.addingTimeInterval(2),
            appIsRunning: false
        )
        #expect(!clockDecision4)
        let clockDecision5 = policy.shouldLaunch(
            at: corrected.addingTimeInterval(3),
            appIsRunning: false
        )
        #expect(clockDecision5)
    }

    @Test("A backward clock correction cannot create duplicate in-flight launches")
    func backwardClockKeepsLaunchCoalescing() {
        var policy = AppSupervisorPolicy()
        let now = Date(timeIntervalSince1970: 10000)
        let clockDecision6 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(clockDecision6)
        let corrected = now.addingTimeInterval(-3600)
        let clockDecision7 = policy.shouldLaunch(at: corrected, appIsRunning: false)
        #expect(!clockDecision7)
        let clockDecision8 = policy.shouldLaunch(
            at: corrected.addingTimeInterval(6),
            appIsRunning: false
        )
        #expect(!clockDecision8)
        policy.launchCompleted(at: corrected.addingTimeInterval(6))
        let clockDecision9 = policy.shouldLaunch(
            at: corrected.addingTimeInterval(6),
            appIsRunning: false
        )
        #expect(clockDecision9)
    }

    @Test("Missing process requests one launch until the callback completes")
    func coalescesLaunches() {
        var policy = AppSupervisorPolicy()
        let now = Date(timeIntervalSince1970: 1000)
        let decision1 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(decision1)
        let decision2 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(!decision2)
        policy.launchCompleted(at: now)
        let decision3 = policy.shouldLaunch(at: now.addingTimeInterval(4), appIsRunning: false)
        #expect(!decision3)
        let decision4 = policy.shouldLaunch(at: now.addingTimeInterval(5), appIsRunning: false)
        #expect(decision4)
    }

    @Test("Repeated crashes back off to sixty seconds and stable operation resets recovery")
    func capsBackoffAndRecovers() {
        var policy = AppSupervisorPolicy()
        var now = Date(timeIntervalSince1970: 1000)
        for delay in [5.0, 10, 20, 40, 60, 60] {
            let decision5 = policy.shouldLaunch(at: now, appIsRunning: false)
            #expect(decision5)
            policy.launchCompleted(at: now)
            let decision6 = policy.shouldLaunch(
                at: now.addingTimeInterval(delay - 1),
                appIsRunning: false
            )
            #expect(!decision6)
            now = now.addingTimeInterval(delay)
        }
        let decision7 = policy.shouldLaunch(at: now, appIsRunning: true)
        #expect(!decision7)
        let decision8 = policy.shouldLaunch(at: now.addingTimeInterval(61), appIsRunning: true)
        #expect(!decision8)
        let decision9 = policy.shouldLaunch(at: now.addingTimeInterval(62), appIsRunning: false)
        #expect(decision9)
    }

    @Test("Repeated kills during an active lockout deadline relaunch without backing off")
    func lockoutDeadlineDisablesBackoff() {
        var policy = AppSupervisorPolicy()
        var now = Date(timeIntervalSince1970: 1000)
        for _ in 0 ..< 6 {
            let decision = policy.shouldLaunch(at: now, appIsRunning: false, lockoutActive: true)
            #expect(decision)
            policy.launchCompleted(at: now)
            now = now.addingTimeInterval(1)
        }
        let coalesced = policy.shouldLaunch(at: now, appIsRunning: false, lockoutActive: true)
        #expect(coalesced)
        let inFlight = policy.shouldLaunch(at: now, appIsRunning: false, lockoutActive: true)
        #expect(!inFlight)
        policy.launchCompleted(at: now)
        // Once the deadline passes, ordinary recovery starts from the base delay.
        let afterLockout = policy.shouldLaunch(
            at: now.addingTimeInterval(1), appIsRunning: false
        )
        #expect(!afterLockout)
        let base = policy.shouldLaunch(at: now.addingTimeInterval(5), appIsRunning: false)
        #expect(base)
    }
}
