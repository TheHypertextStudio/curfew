import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
struct BackgroundServiceTests {
    @Test("A replacement build registers after a successful package uninstall")
    func unregisterAllowsUpgradeRegistration() throws {
        let suite = "BackgroundUpgradeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BackgroundServiceStub(status: .notRegistered)
        let manager = BackgroundServiceManager(service: service, preferences: defaults)
        manager.ensureRegistered()
        service.status = .enabled
        try manager.unregister()
        let replacement = BackgroundServiceManager(service: service, preferences: defaults)
        replacement.ensureRegistered()
        #expect(service.registerCount == 2)
    }

    @Test("Background registration retires the legacy guard only after approval")
    func migrationWaitsForEnabledService() {
        let service = BackgroundServiceStub(status: .notRegistered)
        var retired = 0
        let manager = BackgroundServiceManager(
            service: service,
            retireLegacyGuard: { retired += 1 }
        )
        manager.ensureRegistered()
        #expect(service.registerCount == 1)
        #expect(manager.status == .requiresApproval)
        #expect(retired == 0)
        service.status = .enabled
        manager.refreshStatus()
        #expect(retired == 1)
        manager.ensureRegistered()
        #expect(service.registerCount == 1)
        #expect(retired == 1)
    }

    @Test("Registration failures preserve the legacy guard and expose an error")
    func registrationFailureIsVisible() {
        let service = BackgroundServiceStub(status: .notRegistered)
        service.fail = true
        var retired = false
        let manager = BackgroundServiceManager(
            service: service,
            retireLegacyGuard: { retired = true }
        )
        manager.ensureRegistered()
        #expect(manager.lastError != nil)
        #expect(manager.status == .notRegistered)
        #expect(!retired)
    }

    @Test("Closing the last window does not terminate enforcement")
    func windowClosureDoesNotTerminate() {
        #expect(!AppDelegate()
            .applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test("Background launch changes presentation without disabling Release enforcement")
    func backgroundLaunchOnlyChangesPresentation() {
        #expect(CurfewLaunchBehavior.isBackgroundLaunch(arguments: ["Curfew", "--background"]))
        #expect(!CurfewLaunchBehavior.isBackgroundLaunch(arguments: ["Curfew"]))
        #expect(CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: false))
    }

    @Test("Supervisor requests one restart and backs off repeated failed launches")
    func supervisorCoalescesAndBacksOff() {
        let now = Date(timeIntervalSince1970: 1000)
        var policy = AppSupervisorPolicy()
        let decision1 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(decision1)
        let decision2 = policy.shouldLaunch(at: now, appIsRunning: false)
        #expect(!decision2)
        policy.launchCompleted(at: now)
        let decision3 = policy.shouldLaunch(at: now.addingTimeInterval(4), appIsRunning: false)
        #expect(!decision3)
        let decision4 = policy.shouldLaunch(at: now.addingTimeInterval(5), appIsRunning: false)
        #expect(decision4)
        policy.launchCompleted(at: now.addingTimeInterval(5))
        let decision5 = policy.shouldLaunch(at: now.addingTimeInterval(10), appIsRunning: false)
        #expect(!decision5)
        let decision6 = policy.shouldLaunch(at: now.addingTimeInterval(15), appIsRunning: false)
        #expect(decision6)
    }

    @Test("A healthy process never receives a duplicate launch")
    func supervisorReusesRunningApp() {
        var policy = AppSupervisorPolicy()
        let now = Date(timeIntervalSince1970: 1000)
        let decision7 = policy.shouldLaunch(at: now, appIsRunning: true)
        #expect(!decision7)
        let decision8 = policy.shouldLaunch(at: now.addingTimeInterval(65), appIsRunning: true)
        #expect(!decision8)
        let decision9 = policy.shouldLaunch(at: now.addingTimeInterval(66), appIsRunning: false)
        #expect(decision9)
    }
}

private final class BackgroundServiceStub: AppServiceControlling {
    var status: SMAppService.Status
    var fail = false
    var registerCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if fail {
            throw CocoaError(.fileWriteUnknown)
        }
        status = .requiresApproval
    }

    func unregister() throws {
        if fail {
            throw CocoaError(.fileWriteUnknown)
        }
        status = .notRegistered
    }
}
