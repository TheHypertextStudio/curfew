@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct RestHandoffCoordinatorTests {
    @MainActor
    private final class Fixture {
        var now: TimeInterval = 1000
        var calls: [String] = []
        var launchResult: RestHandoffPolicy.LaunchResult = .started
        var duringSettle: (() -> Void)?
        var duringRefresh: (() -> Void)?
        lazy var coordinator = RestHandoffCoordinator(
            operations: .init(
                settle: { [self] in
                    calls.append("settle")
                    duringSettle?()
                    try Task.checkCancellation()
                },
                launch: { [self] in calls.append("launch"); return launchResult },
                refreshTime: { [self] in calls.append("time"); duringRefresh?() },
                refreshAuthority: { [self] in calls.append("authority"); duringRefresh?() }
            ), uptime: { [self] in now }
        )
    }

    @Test("Live effects settle and launch only after sixty idle seconds")
    func idleEffects() async {
        let fixture = Fixture()
        let coordinator = fixture.coordinator
        await coordinator.handle(.restNow)?.value
        #expect(fixture.calls.isEmpty)
        coordinator.handle(.reflectionResolved(.submitted))
        fixture.now += 59.999
        await coordinator.handle(.idleCheck)?.value
        #expect(fixture.calls.isEmpty)
        fixture.now += 0.001
        await coordinator.handle(.idleCheck)?.value
        #expect(fixture.calls == ["settle", "launch"])
        #expect(coordinator.policy.phase == .saver)
        #expect(!coordinator.policy.controlsMayReturn)
    }

    @Test("Input during settling cancels the launch and preserves interactive controls")
    func cancellation() async {
        let fixture = Fixture()
        let coordinator = fixture.coordinator
        coordinator.handle(.reflectionResolved(.skipped))
        fixture.duringSettle = { coordinator.handle(.input) }
        await coordinator.handle(.restNow)?.value
        #expect(fixture.calls == ["settle"])
        #expect(coordinator.policy.phase == .interactive)
        #expect(coordinator.policy.controlsMayReturn)
    }

    @Test("Return refreshes current time and authority before permitting content")
    func refreshBarrierAndReentry() async {
        let fixture = Fixture()
        let coordinator = fixture.coordinator
        coordinator.handle(.reflectionResolved(.submitted))
        await coordinator.handle(.restNow)?.value
        fixture.duringRefresh = { #expect(!coordinator.policy.controlsMayReturn) }
        fixture.now += 10
        await coordinator.handle(.saverReturned)?.value
        #expect(fixture.calls == ["settle", "launch", "time", "authority"])
        #expect(coordinator.policy.controlsMayReturn)
        await coordinator.handle(.idleCheck)?.value
        #expect(fixture.calls.count == 4)
        fixture.now += 60
        await coordinator.handle(.idleCheck)?.value
        #expect(fixture.calls.suffix(2) == ["settle", "launch"])
    }

    @Test("Launch failure restores a usable experience and an explicit setup state")
    func failureAndBlockers() async {
        let fixture = Fixture()
        fixture.launchResult = .unavailable(.companionUnavailable)
        let coordinator = fixture.coordinator
        coordinator.handle(.reflectionResolved(.skipped))
        for blocker in [RestHandoffPolicy.Blocker.editing, .confirmation, .recovery] {
            coordinator.handle(.setBlocker(blocker, active: true))
            await coordinator.handle(.restNow)?.value
            #expect(fixture.calls.isEmpty)
            coordinator.handle(.setBlocker(blocker, active: false))
        }
        await coordinator.handle(.restNow)?.value
        #expect(coordinator.policy.setupStatus == .companionUnavailable)
        #expect(coordinator.policy.controlsMayReturn)
        #expect(coordinator.policy.phase == .interactive)
        coordinator.reset()
        #expect(coordinator.policy.setupStatus == nil)
        await coordinator.handle(.restNow)?.value
        #expect(fixture.calls.count == 2)
    }
}
