import Foundation
@testable import CurfewKit
import Testing

// Proposed Foundation-only contract. UNEXECUTED against temporary inert scaffold.
// Authorization and absolute occurrence times are helper-resolved inputs, never
// trusted merely because an app encoded them. No power or XPC APIs run here.
struct SunriseWakePlannerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let occurrenceID = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
    private let otherID = UUID(uuidString: "51000000-0000-0000-0000-000000000002")!
    private let owner = "studio.hypertext.curfew.dev.sunrise"

    private var planner: SunriseWakePlanner { SunriseWakePlanner(owner: owner) }

    private func plan(
        enabled: Bool = true,
        leadMinutes: Int = 30,
        allowsBattery: Bool = false,
        onExternalPower: Bool = true,
        unlockOffset: TimeInterval = 7200
    ) throws -> SunriseWakePlan? {
        try planner.makePlan(
            enabled: enabled,
            requestedOccurrenceID: occurrenceID,
            authorizedOccurrenceID: occurrenceID,
            lockedAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(unlockOffset),
            leadMinutes: leadMinutes,
            allowsBattery: allowsBattery,
            onExternalPower: onExternalPower,
            now: now
        )
    }

    @Test("Automatic wake requires explicit opt-in")
    func disabledProducesNoPlan() throws {
        #expect(try plan(enabled: false) == nil)
        #expect(try planner.makePlan(
            requestedOccurrenceID: occurrenceID,
            authorizedOccurrenceID: occurrenceID,
            lockedAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(7200),
            leadMinutes: 30,
            allowsBattery: false,
            onExternalPower: true,
            now: now
        ) == nil)
    }

    @Test("Wake and display hold use the authorized absolute unlock")
    func absoluteTimingAndFixedEvent() throws {
        let result = try #require(try plan())
        #expect(result.occurrenceID == occurrenceID)
        #expect(result.owner == owner)
        #expect(result.wakeAt == now.addingTimeInterval(5400))
        #expect(result.holdUntil == now.addingTimeInterval(7500))
        #expect(result.allowsBattery == false)
        #expect(SunriseWakePlan.eventType == "wake")
    }

    @Test("Lead-in endpoints are inclusive", arguments: [5, 60])
    func leadBoundsAccepted(minutes: Int) throws {
        let result = try #require(try plan(leadMinutes: minutes))
        #expect(result.wakeAt == now.addingTimeInterval(7200 - Double(minutes * 60)))
    }

    @Test("Out-of-range lead-in is rejected", arguments: [-1, 0, 4, 61, Int.max])
    func leadBoundsRejected(minutes: Int) {
        #expect(throws: SunriseWakePlanner.ValidationError.invalidLeadMinutes) {
            try plan(leadMinutes: minutes)
        }
    }

    @Test("A request cannot substitute a different occurrence")
    func unauthorizedOccurrenceRejected() {
        #expect(throws: SunriseWakePlanner.ValidationError.unauthorizedOccurrence) {
            try planner.makePlan(
                enabled: true,
                requestedOccurrenceID: otherID,
                authorizedOccurrenceID: occurrenceID,
                lockedAt: now.addingTimeInterval(-3600),
                unlockAt: now.addingTimeInterval(7200),
                leadMinutes: 30,
                allowsBattery: false,
                onExternalPower: true,
                now: now
            )
        }
    }

    @Test("Reversed or zero-length occurrence is rejected", arguments: [0.0, -1.0])
    func invalidOccurrenceRejected(duration: TimeInterval) {
        #expect(throws: SunriseWakePlanner.ValidationError.invalidOccurrence) {
            try planner.makePlan(
                enabled: true,
                requestedOccurrenceID: occurrenceID,
                authorizedOccurrenceID: occurrenceID,
                lockedAt: now.addingTimeInterval(7200),
                unlockAt: now.addingTimeInterval(7200 + duration),
                leadMinutes: 30,
                allowsBattery: false,
                onExternalPower: true,
                now: now
            )
        }
    }

    @Test("A wake at or before now cannot become a stale scheduled event", arguments: [-1.0, 0.0, 1800.0])
    func expiredWakeRejected(unlockOffset: TimeInterval) {
        #expect(throws: SunriseWakePlanner.ValidationError.expired) {
            try plan(unlockOffset: unlockOffset)
        }
    }

    @Test("AC-only policy excludes battery and explicit opt-in allows battery")
    func powerPolicyIsExplicit() throws {
        #expect(throws: SunriseWakePlanner.ValidationError.batteryExcluded) {
            try plan(onExternalPower: false)
        }
        let batteryPlan = try #require(try plan(allowsBattery: true, onExternalPower: false))
        #expect(batteryPlan.allowsBattery)
    }

    @Test("Non-finite helper timestamps are rejected", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteTimestampsRejected(value: Double) {
        for field in 0..<3 {
            #expect(throws: SunriseWakePlanner.ValidationError.invalidTimestamp) {
                try planner.makePlan(
                    enabled: true,
                    requestedOccurrenceID: occurrenceID,
                    authorizedOccurrenceID: occurrenceID,
                    lockedAt: field == 0 ? Date(timeIntervalSince1970: value) : now.addingTimeInterval(-3600),
                    unlockAt: field == 1 ? Date(timeIntervalSince1970: value) : now.addingTimeInterval(7200),
                    leadMinutes: 30,
                    allowsBattery: false,
                    onExternalPower: true,
                    now: field == 2 ? Date(timeIntervalSince1970: value) : now
                )
            }
        }
    }

    @Test("Repeated plan does not reschedule an already owned event")
    func identicalPlanDeduplicated() throws {
        let current = try #require(try plan())
        let change = planner.reconcile(current: current, desired: current)
        #expect(change.cancel == nil)
        #expect(change.schedule == nil)
    }

    @Test("Changed timing replaces the owned plan and disable cancels it")
    func replaceAndCancelOwnedPlan() throws {
        let current = try #require(try plan())
        let desired = try #require(try plan(leadMinutes: 15))
        let replacement = planner.reconcile(current: current, desired: desired)
        #expect(replacement.cancel == current)
        #expect(replacement.schedule == desired)
        let cancellation = planner.reconcile(current: current, desired: nil)
        #expect(cancellation.cancel == current)
        #expect(cancellation.schedule == nil)
        let empty = planner.reconcile(current: nil, desired: nil)
        #expect(empty.cancel == nil)
        #expect(empty.schedule == nil)
    }

    @Test("Cancellation never claims another owner or app flavor's event")
    func foreignOwnerIsNeverCancelled() throws {
        let foreign = try #require(try SunriseWakePlanner(owner: "another.product.sunrise").makePlan(
            enabled: true,
            requestedOccurrenceID: occurrenceID,
            authorizedOccurrenceID: occurrenceID,
            lockedAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(7200),
            leadMinutes: 30,
            allowsBattery: false,
            onExternalPower: true,
            now: now
        ))
        let cancellation = planner.reconcile(current: foreign, desired: nil)
        #expect(cancellation.cancel == nil)
        #expect(cancellation.schedule == nil)
    }

    @Test("A foreign desired plan cannot schedule or replace this owner's event")
    func foreignDesiredOwnerCannotSchedule() throws {
        let foreign = try #require(try SunriseWakePlanner(owner: "another.product.sunrise").makePlan(
            enabled: true,
            requestedOccurrenceID: occurrenceID,
            authorizedOccurrenceID: occurrenceID,
            lockedAt: now.addingTimeInterval(-3600),
            unlockAt: now.addingTimeInterval(7200),
            leadMinutes: 30,
            allowsBattery: false,
            onExternalPower: true,
            now: now
        ))
        let current = try #require(try plan())
        for existing in [nil, Optional(current)] {
            let change = planner.reconcile(current: existing, desired: foreign)
            #expect(change.cancel == nil)
            #expect(change.schedule == nil)
        }
    }

}
