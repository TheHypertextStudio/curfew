@testable import CurfewKit
import Foundation
import Testing

/// Prepared contracts only; no native display or power APIs are invoked.
struct SunriseDisplayDeliveryTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let occurrenceID = UUID()

    private func plan(allowsBattery: Bool = false) -> SunriseWakePlan {
        SunriseWakePlan(
            owner: "curfew.test",
            occurrenceID: occurrenceID,
            wakeAt: now,
            holdUntil: now.addingTimeInterval(900),
            allowsBattery: allowsBattery
        )
    }

    private func subject(_ effects: Effects) -> SunriseDisplayDelivery {
        SunriseDisplayDelivery(
            declareUserActivity: {
                effects.calls.append("activity")
                if effects.failActivity {
                    throw Failure.native
                }
            },
            acquireDisplayAssertion: { until in
                effects.calls.append("acquire")
                effects.deadlines.append(until)
                if effects.failAcquire {
                    throw Failure.native
                }
                return effects.token
            },
            releaseDisplayAssertion: { token in
                effects.calls.append("release")
                effects.released.append(token)
                if effects.failRelease {
                    throw Failure.native
                }
            }
        )
    }

    private func deliver(
        _ subject: SunriseDisplayDelivery, plan: SunriseWakePlan,
        enabled: Bool = true, batteryOptIn: Bool = false,
        externalPower: Bool = true, at: Date? = nil
    ) throws -> SunriseDisplayDelivery.Outcome {
        try subject.reconcile(
            plan: plan,
            enabled: enabled,
            batteryOptIn: batteryOptIn,
            onExternalPower: externalPower,
            now: at ?? now
        )
    }

    @Test("Delivery uses absolute half-open window and exact bounded deadline")
    func absoluteWindow() throws {
        for offset in [-1.0, 0, 899, 900, 901] {
            let effects = Effects()
            let service = subject(effects)
            let result = try deliver(service, plan: plan(), at: now.addingTimeInterval(offset))
            if offset >= 0, offset < 900 {
                #expect(result == .active)
                #expect(service.isActive)
                #expect(effects.calls == ["activity", "acquire"])
                #expect(effects.deadlines == [plan().holdUntil])
            } else {
                #expect(result == .inactive)
                #expect(!service.isActive)
                #expect(effects.calls.isEmpty)
            }
        }
        // The planner's holdUntil is unlockAt + 300; delivery never extends it.
        #expect(plan().holdUntil == now.addingTimeInterval(600 + 300))
    }

    @Test("Feature defaults off before any user activity")
    func defaultOff() throws {
        let effects = Effects()
        let service = subject(effects)
        #expect(try service.reconcile(plan: plan(), onExternalPower: true, now: now) == .inactive)
        #expect(effects.calls.isEmpty)
        #expect(!service.isActive)
    }

    @Test("Battery needs both plan allowance and separate display opt-in")
    func batteryAdmission() throws {
        for planAllowance in [false, true] {
            for optIn in [false, true] {
                let effects = Effects()
                let service = subject(effects)
                let result = try deliver(
                    service,
                    plan: plan(allowsBattery: planAllowance),
                    batteryOptIn: optIn,
                    externalPower: false
                )
                if planAllowance, optIn {
                    #expect(result == .active)
                    #expect(effects.calls == ["activity", "acquire"])
                } else {
                    #expect(result == .batteryExcluded)
                    #expect(effects.calls.isEmpty)
                    #expect(!service.isActive)
                }
            }
        }
    }

    @Test("Repeated system-wake and timer notifications deliver once per occurrence")
    func deduplicates() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        _ = try deliver(service, plan: plan(), at: now.addingTimeInterval(1))
        #expect(effects.calls == ["activity", "acquire"])
    }

    @Test("Disable, dismissal, power loss, expiry and teardown release only owned token")
    func lifecycleRelease() throws {
        for stop in 0 ... 4 {
            let effects = Effects()
            let service = subject(effects)
            _ = try deliver(service, plan: plan())
            switch stop {
            case 0: _ = try deliver(service, plan: plan(), enabled: false)
            case 1: try service.dismiss(occurrenceID: occurrenceID)
            case 2: _ = try deliver(service, plan: plan(), externalPower: false)
            case 3: _ = try deliver(service, plan: plan(), at: plan().holdUntil)
            default: try service.stop()
            }
            #expect(effects.released == [effects.token])
            #expect(!service.isActive)
            try service.stop()
            #expect(effects.released == [effects.token])
        }
    }

    @Test("Dismissal is sticky for this occurrence and cannot release foreign tokens")
    func dismissalDoesNotRearm() throws {
        let effects = Effects()
        let service = subject(effects)
        try service.dismiss(occurrenceID: UUID())
        #expect(effects.calls.isEmpty)
        _ = try deliver(service, plan: plan())
        try service.dismiss(occurrenceID: UUID())
        #expect(service.isActive)
        try service.dismiss(occurrenceID: occurrenceID)
        #expect(try deliver(service, plan: plan()) == .dismissed)
        #expect(effects.calls == ["activity", "acquire", "release"])
    }

    @Test("Nonfinite time and inverted plan cannot activate display")
    func invalidTime() throws {
        let invalidPlans = [
            SunriseWakePlan(
                owner: "curfew.test",
                occurrenceID: occurrenceID,
                wakeAt: now,
                holdUntil: now,
                allowsBattery: false
            ),
            SunriseWakePlan(
                owner: "curfew.test",
                occurrenceID: occurrenceID,
                wakeAt: now,
                holdUntil: now.addingTimeInterval(-1),
                allowsBattery: false
            ),
            SunriseWakePlan(
                owner: "curfew.test",
                occurrenceID: occurrenceID,
                wakeAt: Date(timeIntervalSince1970: .infinity),
                holdUntil: plan().holdUntil,
                allowsBattery: false
            ),
            SunriseWakePlan(
                owner: "curfew.test",
                occurrenceID: occurrenceID,
                wakeAt: now,
                holdUntil: Date(timeIntervalSince1970: .nan),
                allowsBattery: false
            )
        ]
        for candidate in invalidPlans {
            let effects = Effects()
            #expect(throws: SunriseDisplayDelivery.Rejection.invalidTimestamp) {
                try deliver(subject(effects), plan: candidate)
            }
            #expect(effects.calls.isEmpty)
        }
        let effects = Effects()
        #expect(throws: SunriseDisplayDelivery.Rejection.invalidTimestamp) {
            try deliver(subject(effects), plan: plan(), at: Date(timeIntervalSince1970: .nan))
        }
        #expect(effects.calls.isEmpty)
    }

    @Test("Native activity and acquisition failures propagate without false active state")
    func activationFailures() throws {
        for activityFailure in [true, false] {
            let effects = Effects()
            effects.failActivity = activityFailure
            effects.failAcquire = !activityFailure
            let service = subject(effects)
            #expect(throws: Failure.native) { try deliver(service, plan: plan()) }
            #expect(!service.isActive)
            #expect(effects.released.isEmpty)
            #expect(effects.calls == (activityFailure ? ["activity"] : ["activity", "acquire"]))
        }
    }

    @Test("Removing the plan releases only the assertion acquired by this delivery")
    func nilPlanReleasesOwnedToken() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        #expect(try service.reconcile(
            plan: nil,
            enabled: true,
            onExternalPower: true,
            now: now
        ) == .inactive)
        #expect(effects.calls == ["activity", "acquire", "release"])
        #expect(effects.released == [effects.token])
        #expect(!service.isActive)
    }

    @Test("A new occurrence releases the old assertion before new display activity")
    func replacementOccurrence() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        let replacement = SunriseWakePlan(
            owner: "curfew.test", occurrenceID: UUID(), wakeAt: now,
            holdUntil: now.addingTimeInterval(600), allowsBattery: false
        )
        #expect(try deliver(service, plan: replacement) == .active)
        #expect(effects.calls == ["activity", "acquire", "release", "activity", "acquire"])
        #expect(effects.released == [effects.token])
        #expect(effects.deadlines == [plan().holdUntil, replacement.holdUntil])
    }

    @Test("Earlier same-occurrence deadline replaces the assertion without repeating activity")
    func shortenedDeadline() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        let replacement = SunriseWakePlan(
            owner: "curfew.test", occurrenceID: occurrenceID, wakeAt: now,
            holdUntil: now.addingTimeInterval(600), allowsBattery: false
        )
        #expect(try deliver(service, plan: replacement) == .active)
        #expect(effects.calls == ["activity", "acquire", "release", "acquire"])
        #expect(effects.released == [effects.token])
        #expect(effects.deadlines == [plan().holdUntil, replacement.holdUntil])
    }

    @Test("Failed replacement cleanup blocks new activity and acquisition until release succeeds")
    func replacementReleaseFailure() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        let replacement = SunriseWakePlan(
            owner: "curfew.test", occurrenceID: UUID(), wakeAt: now,
            holdUntil: now.addingTimeInterval(600), allowsBattery: false
        )
        effects.failRelease = true
        #expect(throws: Failure.native) { try deliver(service, plan: replacement) }
        #expect(!service.isActive)
        #expect(effects.calls == ["activity", "acquire", "release"])
        #expect(effects.deadlines == [plan().holdUntil])
        #expect(effects.released == [effects.token])

        effects.failRelease = false
        #expect(try deliver(service, plan: replacement) == .active)
        #expect(effects.calls == [
            "activity",
            "acquire",
            "release",
            "release",
            "activity",
            "acquire"
        ])
        #expect(effects.released == [effects.token, effects.token])
        #expect(effects.deadlines == [plan().holdUntil, replacement.holdUntil])
    }

    @Test("Cleanup without a successful acquisition cannot release any foreign token")
    func noUnownedRelease() throws {
        let effects = Effects()
        let service = subject(effects)
        try service.stop()
        try service.dismiss(occurrenceID: occurrenceID)
        _ = try service.reconcile(plan: nil, enabled: true, onExternalPower: true, now: now)
        #expect(effects.released.isEmpty)
        #expect(effects.calls.isEmpty)
    }

    @Test("Release failure is reported, inactive, and retains owned token for retry")
    func releaseFailure() throws {
        let effects = Effects()
        let service = subject(effects)
        _ = try deliver(service, plan: plan())
        effects.failRelease = true
        #expect(throws: Failure.native) { try service.stop() }
        #expect(!service.isActive)
        effects.failRelease = false
        try service.stop()
        #expect(effects.released == [effects.token, effects.token])
    }

    private enum Failure: Error, Equatable { case native }

    private final class Effects {
        let token = SunriseDisplayDelivery.AssertionToken(rawValue: 42)
        var calls: [String] = []
        var deadlines: [Date] = []
        var released: [SunriseDisplayDelivery.AssertionToken] = []
        var failActivity = false
        var failAcquire = false
        var failRelease = false
    }
}
