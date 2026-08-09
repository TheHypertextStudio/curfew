@testable import Curfew
import Foundation
import Testing

/// The wiring: what makes a report happen, and what a failed one must not do.
@MainActor
struct DeviceStatusWiringTests {
    // MARK: - Off by default

    @Test("A default-configured model never publishes anything, however long it runs")
    func defaultModelNeverPublishes() async {
        let harness = DeviceStatusWiringHarness()

        for _ in 0 ..< 20 {
            harness.model.tick()
        }
        await harness.settle()

        #expect(harness.transport.calls.isEmpty)
        #expect(!harness.model.isDeviceStatusReportingLive)
    }

    @Test("Reporting stays off until an endpoint resolves")
    func enabledWithoutAnEndpointPublishesNothing() async {
        var reporting = DeviceStatusWiringHarness.configured()
        reporting.baseURL = ""
        let harness = DeviceStatusWiringHarness(reporting: reporting)

        for _ in 0 ..< 5 {
            harness.model.tick()
        }
        await harness.settle()

        #expect(harness.transport.calls.isEmpty)
    }

    @Test("A plain-HTTP endpoint is refused rather than downgraded")
    func plainHTTPEndpointIsRefused() async {
        var reporting = DeviceStatusWiringHarness.configured()
        reporting.baseURL = "http://coordinator.example"
        let harness = DeviceStatusWiringHarness(reporting: reporting)

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        #expect(harness.transport.calls.isEmpty)
    }

    // MARK: - Enforcement transitions

    @Test("An enforcement phase transition publishes a report carrying the new phase")
    func enforcementTransitionPublishes() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(),
            schedule: DeviceStatusWiringHarness.allDayLocked
        )
        let model = harness.model
        // Hermetic start, as `LifecycleWiringTests` does it: seed a known
        // non-locked phase and clear any durable record, so the first tick
        // produces a real `.dayOff -> .locked` transition rather than starting
        // out already locked.
        model.lockoutDeadlineStore.clear()
        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        model.tick()
        await harness.settle()

        #expect(model.state.phase == .locked)
        #expect(harness.transport.calls.count >= 1)
        #expect(harness.publishedPhase(at: 0) == "locked")
        // A locked device says when the lockout ends, which is the field
        // another machine needs to render "back at 9".
        let body = harness.transport.decodedBody(at: 0)
        #expect(!(body?["activeLockoutEndsAt"] is NSNull))
    }

    @Test("Leaving lockout publishes the phase it left for")
    func leavingLockoutPublishes() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(),
            schedule: DeviceStatusWiringHarness.allDayLocked
        )
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
        model.tick()

        model.lockoutDeadlineStore.clear()
        model.settings.schedule = DeviceStatusWiringHarness.allDaysOff
        model.tick()
        await harness.settle()

        #expect(model.state.phase == .dayOff)
        #expect(harness.transport.publishedVersions.count >= 2)
        let last = harness.transport.calls.count - 1
        #expect(harness.publishedPhase(at: last) == "day_off")
        #expect(harness.transport.decodedBody(at: last)?["activeLockoutEndsAt"] is NSNull)
    }

    // MARK: - Presence transitions

    @Test("A presence transition publishes a report")
    func presenceTransitionPublishes() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )
        let model = harness.model
        model.settings.presence.cameraEnabled = true
        model.tick()
        await harness.settle()
        let beforeTransition = harness.transport.calls.count

        // The camera sees a person while HID is idle: `.unknown -> .presentButIdle`.
        harness.sensor.observe(.detected, at: Date())
        model.tick()
        await harness.settle()

        #expect(model.presenceState == .presentButIdle)
        #expect(harness.transport.calls.count > beforeTransition)
    }

    @Test("A presence report still carries no presence, because the schema has no field for it")
    func presenceReportCarriesNoPresence() async throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )
        let model = harness.model
        model.settings.presence.cameraEnabled = true
        model.tick()
        harness.sensor.observe(.detected, at: Date())
        model.tick()
        await harness.settle()

        let last = harness.transport.calls.count - 1
        let body = try #require(harness.transport.decodedBody(at: last))
        // Not a wish list — an assertion that this build has not quietly coined
        // a field curfew-protocols never defined.
        #expect(Set(body.keys) == DeviceStatusReport.schemaKeys)
        #expect(body["presence"] == nil)
        #expect(body["presenceState"] == nil)
        #expect(body["personSignal"] == nil)
        #expect(body["cameraEnabled"] == nil)
    }

    // MARK: - Heartbeat

    @Test("The heartbeat publishes on cadence and not before")
    func heartbeatRespectsTheCadence() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60)
        )
        let model = harness.model

        // First tick: the cadence has never fired, so one report goes out.
        model.tick()
        await harness.settle()
        #expect(harness.transport.calls.count == 1)

        // Ten more ticks inside the same minute publish nothing further —
        // otherwise a coordinator would take one report a second forever.
        for _ in 0 ..< 10 {
            model.tick()
        }
        await harness.settle()
        #expect(harness.transport.calls.count == 1)
    }

    @Test("Every published version is strictly increasing")
    func publishedVersionsAreStrictlyIncreasing() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(heartbeatSeconds: 60)
        )

        for _ in 0 ..< 6 {
            harness.model.publishDeviceStatus(trigger: .configuration)
            await harness.settle()
        }

        let versions = harness.transport.publishedVersions
        #expect(versions.count == 6)
        #expect(versions == versions.sorted())
        #expect(Set(versions).count == versions.count)
    }

    // MARK: - Configuration

    @Test("Turning reporting on mints a schema-valid device identifier once")
    func enablingMintsADeviceIdentifier() async {
        let harness = DeviceStatusWiringHarness()
        let model = harness.model
        model.settings.statusReporting.baseURL = "https://coordinator.example"

        model.enableDeviceStatusReporting()
        let minted = model.settings.statusReporting.deviceID

        #expect(minted.range(
            of: DeviceStatusReport.deviceIDPattern,
            options: .regularExpression
        ) != nil)

        // Off and on again keeps the same identity, so a coordinator does not
        // see a second Mac appear.
        model.disableDeviceStatusReporting()
        model.enableDeviceStatusReporting()
        #expect(model.settings.statusReporting.deviceID == minted)
        await harness.settle()
    }

    @Test("The report goes to the configured endpoint")
    func reportUsesTheConfiguredEndpoint() async throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        let call = try #require(harness.transport.calls.first)
        // The path curfew-sync implements: `src/routes/device-status.ts`
        // mounted at `/sync` by `src/worker.ts`. Written out rather than built
        // from `DeviceStatusReportingPolicy.statusPath`, so renaming the
        // constant fails here instead of silently agreeing with itself.
        #expect(call.endpoint.absoluteString == "https://coordinator.example/sync/status")
    }

    @Test("What reaches the transport is a DeviceStatusPublication, not a snapshot")
    func publishedBodyIsAPublication() async throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        let body = try #require(harness.transport.decodedBody(at: 0))
        // `parseDeviceStatusPublication` rejects a body missing either of
        // these, so a report without them is a guaranteed 400 on every publish.
        #expect(body["type"] as? String == "status")
        let cursor = try #require(body["cursor"] as? String)
        #expect(cursor.range(of: "^[A-Za-z0-9_-]{22,128}$", options: .regularExpression) != nil)
    }
}
