@testable import CurfewKit
import Foundation
import Testing

@MainActor
struct AccountStatusPublicationLedgerTests {
    @Test("A disarmed schedule cannot publish an active lockout")
    func disarmedScheduleIsNotAnEnforcedLock() throws {
        var value = report(version: 1, phase: .locked)
        value.activeLockoutEndsAt = Date().addingTimeInterval(600)
        value.isEnforcementEnabled = false
        let body = try #require(
            JSONSerialization.jsonObject(with: value.encodedBody()) as? [String: Any]
        )
        #expect(body["phase"] as? String == "unknown")
        #expect(body["activeLockoutEndsAt"] is NSNull)
        #expect(body["nextTransitionAt"] is NSNull)
    }

    private func report(version: Int, phase: EnforcementPhase = .working) -> DeviceStatusReport {
        DeviceStatusReport(
            deviceID: "20000000-0000-4000-8000-000000000001",
            phase: phase,
            timeZone: "America/Los_Angeles",
            scheduleDigest: String(repeating: "S", count: 43),
            statusVersion: version,
            observedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(version)),
            nextTransitionAt: Date(timeIntervalSince1970: 1_800_003_600),
            activeLockoutEndsAt: nil
        )
    }

    @Test("Acknowledged unchanged heartbeats do not create another status publication")
    func acknowledgedHeartbeatIsSuppressed() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        ledger.finish(first, succeeded: true)

        #expect(ledger.begin(report(version: 2)) == nil)
    }

    @Test("An acknowledged status is refreshed when its heartbeat interval elapses")
    func acknowledgedStatusGetsFreshHeartbeat() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        ledger.finish(first, succeeded: true)

        #expect(ledger.begin(report(version: 61)) != nil)
    }

    @Test("An unchanged report retries after publication fails")
    func failedAttemptIsNotAcknowledged() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        ledger.finish(first, succeeded: false)

        #expect(ledger.begin(report(version: 2)) != nil)
    }

    @Test("Identical heartbeats coalesce while a publication is in flight")
    func inFlightHeartbeatsAreCoalesced() throws {
        let ledger = AccountStatusPublicationLedger()
        _ = try #require(ledger.begin(report(version: 1)))

        #expect(ledger.begin(report(version: 2)) == nil)
    }

    @Test("A late failed attempt cannot invalidate a newer acknowledgement")
    func lateFailureIsFenced() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        let changed = try #require(ledger.begin(report(version: 2, phase: .warning)))
        ledger.finish(changed, succeeded: true)
        ledger.finish(first, succeeded: false)

        #expect(ledger.begin(report(version: 3, phase: .warning)) == nil)
    }

    @Test("A state change and return cannot reuse an earlier acknowledgement")
    func failedIntermediateStateCannotReviveAcknowledgement() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        ledger.finish(first, succeeded: true)
        let changed = try #require(ledger.begin(report(version: 2, phase: .warning)))
        ledger.finish(changed, succeeded: false)

        #expect(ledger.begin(report(version: 3)) != nil)
    }

    @Test("Late acknowledgement cannot confirm a newer attempted frame")
    func lateAcknowledgementIsFenced() throws {
        let ledger = AccountStatusPublicationLedger()
        let first = try #require(ledger.begin(report(version: 1)))
        let changed = try #require(ledger.begin(report(version: 2, phase: .warning)))
        ledger.finish(first, succeeded: true)
        ledger.finish(changed, succeeded: false)

        #expect(ledger.begin(report(version: 3, phase: .warning)) != nil)
    }

    @Test("Only publication metadata is excluded from semantic comparison")
    func enforcementFieldsAreNeverSuppressed() throws {
        let base = report(version: 1)
        var mutations: [DeviceStatusReport] = []
        var changed = base
        changed.deviceID = "20000000-0000-4000-8000-000000000002"
        mutations.append(changed)
        changed = base
        changed.phase = .warning
        mutations.append(changed)
        changed = base
        changed.timeZone = "America/New_York"
        mutations.append(changed)
        changed = base
        changed.scheduleDigest = String(repeating: "T", count: 43)
        mutations.append(changed)
        changed = base
        changed.nextTransitionAt = nil
        mutations.append(changed)
        changed = base
        changed.activeLockoutEndsAt = Date(timeIntervalSince1970: 1_800_001_000)
        mutations.append(changed)
        for mutation in mutations {
            let ledger = AccountStatusPublicationLedger()
            let first = try #require(ledger.begin(base))
            ledger.finish(first, succeeded: true)
            #expect(ledger.begin(mutation) != nil)
        }
    }
}
