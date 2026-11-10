@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
struct RestSaverLauncherTests {
    @MainActor
    private final class Fixture {
        var url: URL? = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        var calls: [String] = []
        var receipt = true
        var running = true
        var cancelOnWait = false
        lazy var launcher = RestSaverLauncher(operations: .init(
            resolve: { [self] in calls.append("resolve"); return url },
            requestReadback: { [self] in calls.append("request") },
            open: { [self] _ in calls.append("open"); running = true; return 1234 },
            hasFullScreenReceipt: { [self] in receipt },
            isRunning: { [self] _ in running },
            stopOwned: { [self] pid in calls.append("stop-\(pid)") },
            waitForReceipt: { [self] in
                calls.append("wait")
                if cancelOnWait {
                    throw CancellationError()
                }
            }
        ))
    }

    @Test("Natural return is consumed once so the same coordinator can hand off again")
    func repeatWithRetainedLauncher() async {
        let fixture = Fixture()
        let runtime = RestHandoffRuntime()
        runtime.launcher = fixture.launcher
        let coordinator = RestHandoffCoordinator(operations: .init(
            settle: {},
            launch: {
                runtime.observeReturn()
                return await fixture.launcher.launch()
            },
            refreshTime: {}, refreshAuthority: {}
        ), uptime: { 1000 })
        runtime.coordinator = coordinator
        coordinator.handle(.reflectionResolved(.skipped))
        for _ in 0 ..< 2 {
            await coordinator.handle(.restNow)?.value
            #expect(coordinator.policy.phase == .saver)
            fixture.running = false
            runtime.sessionIsActive = false
            await runtime.observeReturn()?.value
            #expect(coordinator.policy.phase == .saver)
            runtime.sessionIsActive = true
            await runtime.observeReturn()?.value
            #expect(coordinator.policy.phase == .interactive)
            #expect(fixture.launcher.ownedProcess == nil)
            #expect(!fixture.launcher.hasReturned)
        }
        #expect(fixture.calls.filter { $0 == "open" }.count == 2)
    }

    @Test("Public launch requires a fresh full-screen companion receipt")
    func actualCompanionRequired() async {
        let fixture = Fixture()
        let result = await fixture.launcher.launch()
        #expect(result == .started)
        #expect(fixture.calls == ["resolve", "request", "open", "wait"])
        #expect(fixture.launcher.ownedProcess == 1234)
        #expect(!fixture.launcher.hasReturned)
        fixture.running = false
        #expect(fixture.launcher.hasReturned)
    }

    @Test("Wrong saver restores the app by stopping only the newly owned engine")
    func wrongCompanion() async {
        let fixture = Fixture()
        fixture.receipt = false
        #expect(await fixture.launcher.launch() == .unavailable(.companionUnavailable))
        #expect(fixture.calls.last == "stop-1234")
        #expect(fixture.launcher.ownedProcess == nil)
    }

    @Test("Unavailable launch and cancelled settling never leave a new saver running")
    func unavailableAndCancelled() async {
        let missing = Fixture()
        missing.url = nil
        #expect(await missing.launcher.launch() == .unavailable(.launchUnavailable))
        #expect(missing.calls == ["resolve"])
        let cancelled = Fixture()
        cancelled.cancelOnWait = true
        #expect(await cancelled.launcher.launch() == .unavailable(.launchUnavailable))
        #expect(cancelled.calls.last == "stop-1234")
        #expect(cancelled.launcher.ownedProcess == nil)
    }
}
