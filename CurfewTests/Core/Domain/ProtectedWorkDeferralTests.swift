@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``ProtectedWorkDeferral``. The property under test is
/// the one that makes the whole feature safe: a claim buys time, and it buys a
/// bounded amount of it. Renewing forever must not extend the bound, because
/// an agent that never stops asking would otherwise switch enforcement off.
struct ProtectedWorkDeferralTests {
    private let bound: TimeInterval = 30 * 60

    @Test("No active work means proceed immediately")
    func noWorkProceeds() {
        var deferral = ProtectedWorkDeferral()
        let decision = deferral.evaluate(
            now: Date(),
            hasActiveWork: false,
            maximumDeferral: bound
        )
        #expect(decision == .proceed)
        #expect(deferral.startedAt == nil)
    }

    @Test("Active work defers, and the window is measured from first refusal")
    func activeWorkDefers() {
        let start = Date()
        var deferral = ProtectedWorkDeferral()
        let first = deferral.evaluate(now: start, hasActiveWork: true, maximumDeferral: bound)
        #expect(first == .deferred(until: start.addingTimeInterval(bound)))
        #expect(deferral.startedAt == start)

        // Ten minutes later the deadline has not moved.
        let later = start.addingTimeInterval(600)
        let second = deferral.evaluate(now: later, hasActiveWork: true, maximumDeferral: bound)
        #expect(second == .deferred(until: start.addingTimeInterval(bound)))
    }

    @Test("Deferral is bounded — the shutdown proceeds once the budget is spent")
    func deferralIsBounded() {
        let start = Date()
        var deferral = ProtectedWorkDeferral()
        _ = deferral.evaluate(now: start, hasActiveWork: true, maximumDeferral: bound)

        let atLimit = start.addingTimeInterval(bound)
        #expect(
            deferral.evaluate(now: atLimit, hasActiveWork: true, maximumDeferral: bound)
                == .proceed
        )
        // Still true a tick later, with the claim as fresh as ever.
        #expect(
            deferral.evaluate(
                now: atLimit.addingTimeInterval(15),
                hasActiveWork: true,
                maximumDeferral: bound
            ) == .proceed
        )
    }

    @Test("Renewing a claim cannot reopen a spent window")
    func renewalCannotReopenTheWindow() {
        let start = Date()
        var deferral = ProtectedWorkDeferral()
        _ = deferral.evaluate(now: start, hasActiveWork: true, maximumDeferral: bound)
        _ = deferral.evaluate(
            now: start.addingTimeInterval(bound),
            hasActiveWork: true,
            maximumDeferral: bound
        )

        // A brand-new claim arriving after the bound is spent buys nothing:
        // `startedAt` is still the original refusal.
        let decision = deferral.evaluate(
            now: start.addingTimeInterval(bound + 60),
            hasActiveWork: true,
            maximumDeferral: bound
        )
        #expect(decision == .proceed)
        #expect(deferral.startedAt == start)
    }

    @Test("Work finishing resets the window for the next due action")
    func finishingWorkResetsTheWindow() {
        let start = Date()
        var deferral = ProtectedWorkDeferral()
        _ = deferral.evaluate(now: start, hasActiveWork: true, maximumDeferral: bound)
        #expect(deferral.startedAt != nil)

        _ = deferral.evaluate(
            now: start.addingTimeInterval(60),
            hasActiveWork: false,
            maximumDeferral: bound
        )
        #expect(deferral.startedAt == nil)
    }

    @Test("A daemon restart resumes the same window rather than a fresh one")
    func restartResumesTheWindow() {
        let start = Date()
        // Stands in for the root-owned marker the daemon persists.
        var resumed = ProtectedWorkDeferral(startedAt: start)
        let decision = resumed.evaluate(
            now: start.addingTimeInterval(bound + 1),
            hasActiveWork: true,
            maximumDeferral: bound
        )
        #expect(decision == .proceed)
    }

    @Test("A zero bound disables deferral entirely")
    func zeroBoundProceeds() {
        var deferral = ProtectedWorkDeferral()
        #expect(
            deferral.evaluate(now: Date(), hasActiveWork: true, maximumDeferral: 0) == .proceed
        )
    }
}
