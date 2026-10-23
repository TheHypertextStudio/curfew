import CurfewKit
import Foundation
import Testing

struct AppSupervisorPolicyTests {
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
}
