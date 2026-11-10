@testable import CurfewKit
import Foundation
import Testing

/// Test-only API proposal. No production scaffold or behavioral RED is claimed.
/// The coordinator emits presentation requests; it cannot change enforcement.
struct RestHandoffPolicyTests {
    private let start: TimeInterval = 1000

    private func ready() -> RestHandoffPolicy {
        var policy = RestHandoffPolicy(monotonicSeconds: start)
        _ = policy.handle(.reflectionResolved(.submitted), monotonicSeconds: start)
        return policy
    }

    @Test("Idle handoff waits sixty seconds after reflection submission or skip")
    func idleBoundary() throws {
        for resolution in [RestHandoffPolicy.ReflectionResolution.submitted, .skipped] {
            var policy = RestHandoffPolicy(monotonicSeconds: start)
            #expect(policy.handle(.idleCheck, monotonicSeconds: start + 600).isEmpty)
            _ = policy.handle(.reflectionResolved(resolution), monotonicSeconds: start + 600)
            #expect(policy.handle(.idleCheck, monotonicSeconds: start + 659.999).isEmpty)
            let effects = policy.handle(.idleCheck, monotonicSeconds: start + 660)
            let generation = try #require(policy.pendingGeneration)
            #expect(effects == [.settle(generation)])
            #expect(policy.handle(.idleCheck, monotonicSeconds: start + 661).isEmpty)
        }
    }

    @Test("Input restarts idle eligibility and cancels a pending handoff")
    func inputResetsAndCancels() throws {
        var policy = ready()
        _ = policy.handle(.input, monotonicSeconds: start + 59)
        #expect(policy.handle(.idleCheck, monotonicSeconds: start + 60).isEmpty)
        _ = policy.handle(.idleCheck, monotonicSeconds: start + 119)
        let generation = try #require(policy.pendingGeneration)
        #expect(policy.handle(.input, monotonicSeconds: start + 120) == [.cancel(generation)])
        #expect(policy.pendingGeneration == nil)
        #expect(policy.phase == .interactive)
        #expect(policy.handle(.idleCheck, monotonicSeconds: start + 179.999).isEmpty)
        #expect(!policy.handle(.idleCheck, monotonicSeconds: start + 180).isEmpty)
    }

    @Test("Editing, confirmation and recovery block idle and Rest now")
    func blockers() throws {
        for blocker in [RestHandoffPolicy.Blocker.editing, .confirmation, .recovery] {
            var policy = ready()
            _ = policy.handle(.setBlocker(blocker, active: true), monotonicSeconds: start)
            #expect(policy.handle(.idleCheck, monotonicSeconds: start + 100).isEmpty)
            #expect(policy.handle(.restNow, monotonicSeconds: start + 100).isEmpty)
            #expect(policy.pendingGeneration == nil)
            _ = policy.handle(.setBlocker(blocker, active: false), monotonicSeconds: start + 100)
            _ = policy.handle(.restNow, monotonicSeconds: start + 100)
            let generation = try #require(policy.pendingGeneration)
            #expect(policy.handle(
                .setBlocker(blocker, active: true),
                monotonicSeconds: start + 101
            ) == [.cancel(generation)])
            #expect(policy.phase == .interactive)
        }
    }

    @Test("Rest now settles immediately only once reflection is resolved")
    func explicitHandoff() throws {
        var unresolved = RestHandoffPolicy(monotonicSeconds: start)
        #expect(unresolved.handle(.restNow, monotonicSeconds: start).isEmpty)
        var policy = ready()
        let effects = policy.handle(.restNow, monotonicSeconds: start)
        let generation = try #require(policy.pendingGeneration)
        #expect(effects == [.settle(generation)])
        #expect(policy.phase == .settling)
        #expect(policy.handle(.restNow, monotonicSeconds: start).isEmpty)
        #expect(policy
            .handle(.settled(generation), monotonicSeconds: start) == [.launchSaver(generation)])
        #expect(policy.handle(.settled(generation), monotonicSeconds: start).isEmpty)
    }

    @Test("Cancelled generations cannot launch or accept a stale launch callback")
    func staleCallbacks() throws {
        var policy = ready()
        _ = policy.handle(.restNow, monotonicSeconds: start)
        let old = try #require(policy.pendingGeneration)
        _ = policy.handle(.input, monotonicSeconds: start)
        #expect(policy.pendingGeneration == nil)
        #expect(policy.handle(.settled(old), monotonicSeconds: start).isEmpty)
        #expect(policy.handle(.launchCompleted(old, .started), monotonicSeconds: start).isEmpty)
        _ = policy.handle(.restNow, monotonicSeconds: start)
        let current = try #require(policy.pendingGeneration)
        #expect(current != old)
        #expect(policy.handle(.settled(old), monotonicSeconds: start).isEmpty)
        #expect(policy.handle(.launchCompleted(old, .started), monotonicSeconds: start).isEmpty)
        #expect(policy.phase == .settling)
        #expect(policy
            .handle(.settled(current), monotonicSeconds: start) == [.launchSaver(current)])
        _ = policy.handle(.input, monotonicSeconds: start)
        #expect(policy.handle(.launchCompleted(current, .started), monotonicSeconds: start).isEmpty)
        #expect(policy.phase == .interactive)
    }

    @Test("Saver return hides controls until fresh time and authority have both arrived")
    func returnRefreshBarrier() throws {
        for authorityFirst in [false, true] {
            var policy = ready()
            _ = policy.handle(.restNow, monotonicSeconds: start)
            let launch = try #require(policy.pendingGeneration)
            _ = policy.handle(.settled(launch), monotonicSeconds: start)
            _ = policy.handle(.launchCompleted(launch, .started), monotonicSeconds: start)
            #expect(policy.phase == .saver)
            let effects = policy.handle(.saverReturned, monotonicSeconds: start + 100)
            let refresh = try #require(policy.pendingGeneration)
            #expect(refresh != launch)
            #expect(effects == [.refreshTime(refresh), .refreshAuthority(refresh)])
            #expect(!policy.controlsMayReturn)
            _ = policy.handle(.input, monotonicSeconds: start + 100)
            _ = policy.handle(.setBlocker(.editing, active: true), monotonicSeconds: start + 100)
            _ = policy.handle(.setBlocker(.editing, active: false), monotonicSeconds: start + 100)
            #expect(!policy.controlsMayReturn)
            #expect(policy.pendingGeneration == refresh)
            _ = policy.handle(.timeRefreshed(launch), monotonicSeconds: start)
            _ = policy.handle(.authorityRefreshed(launch), monotonicSeconds: start)
            #expect(!policy.controlsMayReturn)
            let first: RestHandoffPolicy
                .Event = authorityFirst ? .authorityRefreshed(refresh) : .timeRefreshed(refresh)
            let second: RestHandoffPolicy
                .Event = authorityFirst ? .timeRefreshed(refresh) : .authorityRefreshed(refresh)
            _ = policy.handle(first, monotonicSeconds: start + 100)
            #expect(!policy.controlsMayReturn)
            _ = policy.handle(second, monotonicSeconds: start + 100)
            #expect(policy.controlsMayReturn)
            #expect(policy.phase == .interactive)
            #expect(policy.pendingGeneration == nil)
            #expect(policy.handle(second, monotonicSeconds: start + 100).isEmpty)
            #expect(policy.handle(.settled(launch), monotonicSeconds: start + 100).isEmpty)
            #expect(policy.handle(.launchCompleted(launch, .started), monotonicSeconds: start + 100)
                .isEmpty)
            #expect(policy.phase == .interactive)
        }
    }

    @Test("Return before launch completion still refreshes and rejects the delayed callback")
    func returnBeforeLaunchCompletion() throws {
        var policy = ready()
        _ = policy.handle(.restNow, monotonicSeconds: start)
        let launch = try #require(policy.pendingGeneration)
        _ = policy.handle(.settled(launch), monotonicSeconds: start)
        let effects = policy.handle(.saverReturned, monotonicSeconds: start + 1)
        let refresh = try #require(policy.pendingGeneration)
        #expect(refresh != launch)
        #expect(policy.phase == .refreshing)
        #expect(effects == [.refreshTime(refresh), .refreshAuthority(refresh)])
        #expect(policy.handle(.launchCompleted(launch, .started), monotonicSeconds: start + 2)
            .isEmpty)
        _ = policy.handle(.timeRefreshed(refresh), monotonicSeconds: start + 2)
        _ = policy.handle(.authorityRefreshed(refresh), monotonicSeconds: start + 2)
        #expect(policy.phase == .interactive)
        #expect(policy.controlsMayReturn)
    }

    @Test("Invalid or backwards monotonic samples cannot trigger handoff")
    func invalidElapsedSamples() {
        for sample in [-1.0, Double.nan, .infinity, -.infinity, start - 1] {
            var policy = ready()
            #expect(policy.handle(.idleCheck, monotonicSeconds: sample).isEmpty)
            #expect(policy.pendingGeneration == nil)
            #expect(policy.phase == .interactive)
            #expect(policy.handle(.idleCheck, monotonicSeconds: start + 59).isEmpty)
            #expect(!policy.handle(.idleCheck, monotonicSeconds: start + 60).isEmpty)
        }
    }

    @Test("Setup failure waits for an explicit retry instead of interrupting each idle minute")
    func unavailableDoesNotLoop() throws {
        var policy = ready()
        _ = policy.handle(.restNow, monotonicSeconds: start)
        let generation = try #require(policy.pendingGeneration)
        _ = policy.handle(.settled(generation), monotonicSeconds: start)
        _ = policy.handle(
            .launchCompleted(generation, .unavailable(.companionUnavailable)),
            monotonicSeconds: start
        )
        #expect(policy.handle(.idleCheck, monotonicSeconds: start + 600).isEmpty)
        #expect(policy.phase == .interactive)
        #expect(!policy.handle(.restNow, monotonicSeconds: start + 600).isEmpty)
    }

    @Test("Unavailable launch keeps the interactive composition with a useful setup status")
    func unavailableLaunch() throws {
        for status in [RestHandoffPolicy.SetupStatus.companionUnavailable, .launchUnavailable] {
            var policy = ready()
            _ = policy.handle(.restNow, monotonicSeconds: start)
            let generation = try #require(policy.pendingGeneration)
            _ = policy.handle(.settled(generation), monotonicSeconds: start)
            _ = policy.handle(
                .launchCompleted(generation, .unavailable(status)),
                monotonicSeconds: start
            )
            #expect(policy.phase == .interactive)
            #expect(policy.controlsMayReturn)
            #expect(policy.pendingGeneration == nil)
            #expect(policy.setupStatus == status)
        }
    }
}
