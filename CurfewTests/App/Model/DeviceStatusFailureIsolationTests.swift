@testable import Curfew
import Foundation
import Testing

/// The load-bearing suite for D4: with the coordinator down, unreachable, or
/// answering rubbish, Curfew still locks the machine exactly when it said it
/// would.
///
/// The method throughout is differential. Each test runs the same enforcement
/// scenario twice — once with reporting off, once with reporting on and the
/// network broken — and asserts the two runs agree on everything enforcement
/// touches. An assertion that the broken run "still locks" would pass even if
/// reporting had shifted a deadline by a minute; comparing against a control
/// will not.
@MainActor
struct DeviceStatusFailureIsolationTests {
    /// Everything about a run that enforcement is responsible for.
    private struct EnforcementOutcome: Equatable {
        var phase: EnforcementPhase
        var warningStage: WarningStage
        var minutesRemaining: Int
        var canRequestExtension: Bool
        var isEnforcingLockout: Bool
        var extensionsRemaining: Int
        var overridesRemaining: Int
        var presenceState: PresenceState
    }

    private func outcome(of model: CurfewAppModel) -> EnforcementOutcome {
        EnforcementOutcome(
            phase: model.state.phase,
            warningStage: model.state.warningStage,
            minutesRemaining: model.state.minutesRemaining,
            canRequestExtension: model.state.canRequestExtension,
            isEnforcingLockout: model.isEnforcingLockout,
            extensionsRemaining: model.extensionsRemaining,
            overridesRemaining: model.overridesRemaining,
            presenceState: model.presenceState
        )
    }

    /// Drives a lockout from a seeded `.dayOff`, the way `LifecycleWiringTests`
    /// does, and returns what enforcement made of it.
    private func driveLockout(_ harness: DeviceStatusWiringHarness) -> EnforcementOutcome {
        let model = harness.model
        model.lockoutDeadlineStore.clear()
        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        for _ in 0 ..< 5 {
            model.tick()
        }
        return outcome(of: model)
    }

    // MARK: - Every failure mode

    @Test(
        "Enforcement is bit-for-bit identical whatever the coordinator does",
        arguments: [
            DeviceStatusPublishOutcome.unreachable,
            .refused(500),
            .refused(503),
            .refused(401),
            .refused(404),
            .stale
        ]
    )
    func enforcementIsUnaffectedByTransportOutcome(
        failure: DeviceStatusPublishOutcome
    ) async {
        let control = DeviceStatusWiringHarness(
            schedule: DeviceStatusWiringHarness.allDayLocked
        )
        let reporting = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60),
            schedule: DeviceStatusWiringHarness.allDayLocked,
            outcome: failure
        )

        let controlOutcome = driveLockout(control)
        let reportingOutcome = driveLockout(reporting)
        await control.settle()
        await reporting.settle()

        #expect(reportingOutcome == controlOutcome)
        #expect(controlOutcome.phase == .locked)
        // The failing run really did try, so this is not passing by never
        // having reached the network at all.
        #expect(!reporting.transport.calls.isEmpty)
        #expect(control.transport.calls.isEmpty)
    }

    // MARK: - A transport that never answers

    @Test("A coordinator that never answers cannot stall the tick loop")
    func aHangingCoordinatorCannotStallEnforcement() async {
        let control = DeviceStatusWiringHarness(
            schedule: DeviceStatusWiringHarness.allDayLocked
        )
        let hanging = BlockingStatusTransport()
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60),
            schedule: DeviceStatusWiringHarness.allDayLocked
        )
        // Swap in a transport that accepts a publish and then never returns.
        // `tick()` is synchronous, so if reporting could block enforcement at
        // all, the ticks below would never come back.
        harness.model.deviceStatusTransportOverride = hanging

        let controlOutcome = driveLockout(control)
        // Five synchronous ticks. If reporting could block enforcement, this
        // call would not have returned — the transport it is talking to never
        // answers.
        let hangingOutcome = driveLockout(harness)

        #expect(hangingOutcome == controlOutcome)
        #expect(hangingOutcome.phase == .locked)

        // Only now, once the test yields, does the publish get a turn — and it
        // is still hanging when it does, which is the point.
        await pumpMainActor()
        #expect(!hanging.calls.isEmpty)

        hanging.release()
        await harness.settle()
    }

    // MARK: - Presence and warnings

    @Test("Presence detection is unaffected by a broken coordinator")
    func presenceIsUnaffected() async {
        let control = DeviceStatusWiringHarness()
        let broken = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60),
            outcome: .unreachable
        )

        for harness in [control, broken] {
            harness.model.settings.presence.cameraEnabled = true
            harness.model.tick()
            harness.sensor.observe(.detected, at: Date())
            harness.model.tick()
        }
        await control.settle()
        await broken.settle()

        #expect(broken.model.presenceState == control.model.presenceState)
        #expect(broken.model.presenceState == .presentButIdle)
        #expect(broken.model.isPresenceCameraLive == control.model.isPresenceCameraLive)
        #expect(!broken.transport.calls.isEmpty)
    }

    @Test("A broken coordinator does not disturb the extension budget")
    func extensionBudgetIsUnaffected() async {
        let control = DeviceStatusWiringHarness()
        let broken = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60),
            outcome: .unreachable
        )

        for harness in [control, broken] {
            harness.model.tick()
            _ = harness.model.extensionTracker.requestExtension(at: harness.model.currentTime)
            harness.model.tick()
        }
        await control.settle()
        await broken.settle()

        #expect(broken.model.extensionTracker.remaining == control.model.extensionTracker.remaining)
    }

    // MARK: - Reporting never becomes load-bearing

    @Test("Turning reporting off mid-run changes nothing about enforcement")
    func disablingMidRunIsInert() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60),
            schedule: DeviceStatusWiringHarness.allDayLocked,
            outcome: .unreachable
        )
        let locked = driveLockout(harness)
        await harness.settle()

        harness.model.disableDeviceStatusReporting()
        let callsAtDisable = harness.transport.calls.count
        #expect(callsAtDisable > 0)
        for _ in 0 ..< 5 {
            harness.model.tick()
        }
        await harness.settle()

        #expect(harness.model.state.phase == locked.phase)
        #expect(harness.model.state.phase == .locked)
        // And it really did stop talking.
        #expect(harness.transport.calls.count == callsAtDisable)
    }
}
