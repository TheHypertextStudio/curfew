@testable import CurfewKit
import Foundation
import Testing

/// Fake C-shaped functions only: these contracts never invoke native power APIs.
struct SunrisePowerIOTests {
    private let date = Date(timeIntervalSince1970: 2_000_000_000)

    private final class Calls {
        var scheduled: [SunrisePowerIO.Event] = []
        var cancelled: [SunrisePowerIO.Event] = []
        var events: [SunrisePowerIO.Event] = []
        var queried = 0
        var declarations = 0
        var releases: [UInt32] = []
        var requests: [SunrisePowerIO.DisplayRequest] = []
        var scheduleCode: Int32 = 0
        var cancelCode: Int32 = 0
        var queryCode: Int32 = 0
        var declareCode: Int32 = 0
        var createCode: Int32 = 0
        var releaseCodes: [UInt32: Int32] = [:]
        var source: String?

        func adapter() -> SunrisePowerIO {
            SunrisePowerIO(owner: "curfew.test", functions: .init(
                schedule: { self.scheduled.append($0); return self.scheduleCode },
                cancel: { self.cancelled.append($0); return self.cancelCode },
                copyScheduled: { self.queried += 1; return (self.queryCode, self.events) },
                declareActivity: { self.declarations += 1; return (self.declareCode, 11) },
                createDisplay: { self.requests.append($0); return (self.createCode, 22) },
                release: { self.releases.append($0); return self.releaseCodes[$0] ?? 0 },
                powerSource: { self.source }
            ))
        }
    }

    private func event(owner: String = "curfew.test", type: String = "wake") -> SunrisePowerIO
        .Event {
        .init(owner: owner, date: date, type: type)
    }

    @Test func scheduleUsesExactFixedOwnerDateAndWake() throws {
        let calls = Calls()
        try calls.adapter().schedule(event())
        #expect(calls.scheduled == [event()])
    }

    @Test func rejectsForeignOrNonWakeBeforeNativeEffects() {
        let calls = Calls()
        let adapter = calls.adapter()
        #expect(throws: SunrisePowerIO.Failure.foreignEvent) {
            try adapter.schedule(event(owner: "foreign"))
        }
        #expect(throws: SunrisePowerIO.Failure.foreignEvent) {
            try adapter.cancel(event(type: "wakepoweron"))
        }
        #expect(calls.scheduled.isEmpty && calls.cancelled.isEmpty && calls.queried == 0)
    }

    @Test func missingExactCancellationDoesNotTouchForeignEvents() throws {
        let calls = Calls()
        calls.events = [
            event(owner: "foreign"),
            event(type: "wakepoweron"),
            .init(owner: "curfew.test", date: date.addingTimeInterval(1), type: "wake")
        ]
        try calls.adapter().cancel(event())
        #expect(calls.queried == 1)
        #expect(calls.cancelled.isEmpty)
    }

    @Test func cancellationQueriesAndCancelsOnlyExactIdentity() throws {
        let calls = Calls()
        calls.events = [event(owner: "foreign"), event()]
        try calls.adapter().cancel(event())
        #expect(calls.cancelled == [event()])
    }

    @Test func invalidEventDatesNeverReachNativeFunctions() {
        for timestamp in [Double.infinity, -.infinity, .nan] {
            let calls = Calls()
            let adapter = calls.adapter()
            let invalid = SunrisePowerIO.Event(
                owner: "curfew.test", date: Date(timeIntervalSince1970: timestamp), type: "wake"
            )
            #expect(throws: (any Error).self) { try adapter.schedule(invalid) }
            #expect(throws: (any Error).self) { try adapter.cancel(invalid) }
            #expect(calls.scheduled.isEmpty && calls.cancelled.isEmpty && calls.queried == 0)
        }
    }

    @Test func nativeErrorsPropagateWithOperationAndCode() {
        let calls = Calls()
        let adapter = calls.adapter()
        calls.scheduleCode = -7
        #expect(throws: SunrisePowerIO.Failure.native(operation: "schedule", code: -7)) {
            try adapter.schedule(event())
        }
        calls.queryCode = -8
        #expect(throws: SunrisePowerIO.Failure.native(operation: "copyScheduled", code: -8)) {
            try adapter.cancel(event())
        }
        calls.queryCode = 0
        calls.events = [event()]
        calls.cancelCode = -9
        #expect(throws: SunrisePowerIO.Failure.native(operation: "cancel", code: -9)) {
            try adapter.cancel(event())
        }
    }

    @Test func activityIsReleasedImmediatelyAndFailedReleaseRetriedByCleanup() throws {
        let calls = Calls()
        let adapter = calls.adapter()
        calls.releaseCodes[11] = -4
        #expect(throws: SunrisePowerIO.Failure.native(operation: "release", code: -4)) {
            try adapter.declareUserActivity()
        }
        #expect(calls.declarations == 1 && calls.releases == [11])
        calls.releaseCodes[11] = 0
        try adapter.cleanup()
        try adapter.cleanup()
        #expect(calls.releases == [11, 11])
    }

    @Test func boundedDisplayAssertionUsesTimeoutReleaseAndOwnedToken() throws {
        let calls = Calls()
        let adapter = calls.adapter()
        let token = try adapter.acquireDisplayAssertion(
            until: date.addingTimeInterval(3900),
            now: date
        )
        #expect(token.rawValue == 22)
        #expect(calls.requests == [.init(
            type: "NoDisplaySleepAssertion",
            timeout: 3900,
            timeoutAction: "TimeoutActionRelease"
        )])
        try adapter.releaseDisplayAssertion(token)
        #expect(calls.releases == [22])
    }

    @Test func invalidTimeoutsNeverCreateAssertions() {
        for interval in [0.0, -1, 3901, .infinity, .nan] {
            let calls = Calls()
            #expect(throws: SunrisePowerIO.Failure.invalidTimeout) {
                try calls.adapter().acquireDisplayAssertion(
                    until: date.addingTimeInterval(interval),
                    now: date
                )
            }
            #expect(calls.requests.isEmpty)
        }
    }

    @Test func nonfiniteCurrentTimeNeverCreatesAnAssertion() {
        for timestamp in [Double.infinity, -.infinity, .nan] {
            let calls = Calls()
            #expect(throws: SunrisePowerIO.Failure.invalidTimeout) {
                try calls.adapter().acquireDisplayAssertion(
                    until: date, now: Date(timeIntervalSince1970: timestamp)
                )
            }
            #expect(calls.requests.isEmpty)
        }
    }

    @Test func foreignAssertionNeverReleasedAndTimedOutOwnedAssertionIsIdempotent() throws {
        let calls = Calls()
        let adapter = calls.adapter()
        #expect(throws: SunrisePowerIO.Failure.foreignAssertion) {
            try adapter.releaseDisplayAssertion(.init(rawValue: 99))
        }
        let token = try adapter.acquireDisplayAssertion(
            until: date.addingTimeInterval(1),
            now: date
        )
        calls.releaseCodes[22] = SunrisePowerIO.notFound
        try adapter.releaseDisplayAssertion(token)
        try adapter.cleanup()
        #expect(calls.releases == [22])
    }

    @Test func cleanupAttemptsAllOwnedIDsRetainsFailuresAndWorksAfterAcquireFailure() throws {
        let calls = Calls()
        let adapter = calls.adapter()
        _ = try adapter.acquireDisplayAssertion(until: date.addingTimeInterval(1), now: date)
        calls.releaseCodes[11] = -4
        #expect(throws: (any Error).self) { try adapter.declareUserActivity() }
        calls.createCode = -5
        #expect(throws: SunrisePowerIO.Failure.native(operation: "createDisplay", code: -5)) {
            try adapter.acquireDisplayAssertion(until: date.addingTimeInterval(1), now: date)
        }
        #expect(throws: (any Error).self) { try adapter.cleanup() }
        #expect(calls.releases.contains(22))
        calls.releaseCodes[11] = 0
        try adapter.cleanup()
        #expect(calls.releases.filter { $0 == 22 }.count == 1)
        #expect(calls.releases.filter { $0 == 11 }.count == 3)
    }

    @Test func declarationFailureNeverClaimsOrReleasesOutputID() {
        let calls = Calls()
        calls.declareCode = -6
        let adapter = calls.adapter()
        #expect(throws: SunrisePowerIO.Failure.native(operation: "declareActivity", code: -6)) {
            try adapter.declareUserActivity()
        }
        try? adapter.cleanup()
        #expect(calls.releases.isEmpty)
    }

    @Test func unknownPowerSourceIsConservative() {
        let calls = Calls()
        let adapter = calls.adapter()
        for source in [nil, "Battery Power", "UPS Power", "unknown"] {
            calls.source = source
            #expect(!adapter.onExternalPower())
        }
        calls.source = "AC Power"
        #expect(adapter.onExternalPower())
    }
}
