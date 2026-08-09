@testable import Curfew
import Foundation
import Testing

/// The two numbers and the one string that decide whether a status report ever
/// reaches a coordinator: where it is posted, and how often.
///
/// Both are transcriptions, and both are asserted against literals rather than
/// against the constants that produce them. A test written as
/// `#expect(policy.statusPath == DeviceStatusReportingPolicy.statusPath)` passes
/// for every possible value, which is exactly how the wrong path shipped once
/// already.
struct DeviceStatusReportingPolicyTests {
    // MARK: - Endpoint

    @Test("The publish path is the one curfew-sync implements")
    func statusPathIsTheImplementedRoute() {
        // `curfew-sync/src/worker.ts` mounts `deviceStatusRoutes` at `/sync`;
        // `src/routes/device-status.ts` registers `POST /status` on it.
        #expect(DeviceStatusReportingPolicy.statusPath == "sync/status")
    }

    @Test("A configured policy resolves to the coordinator's status endpoint")
    func resolvedEndpointIsTheStatusRoute() throws {
        let policy = DeviceStatusReportingPolicy(
            isEnabled: true,
            baseURL: "https://coordinator.example",
            deviceToken: "token",
            deviceID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
            heartbeatSeconds: 60
        )

        let endpoint = try #require(policy.resolvedEndpoint)
        #expect(endpoint.absoluteString == "https://coordinator.example/sync/status")
    }

    @Test("A base URL carrying a path prefix keeps it")
    func resolvedEndpointRespectsAPathPrefix() throws {
        // Coordinators behind a shared host are a real deployment, and the
        // route is mounted relative to whatever the app is served under.
        let policy = DeviceStatusReportingPolicy(
            isEnabled: true,
            baseURL: "https://example.test/curfew",
            deviceToken: "",
            deviceID: "",
            heartbeatSeconds: 60
        )

        let endpoint = try #require(policy.resolvedEndpoint)
        #expect(endpoint.absoluteString == "https://example.test/curfew/sync/status")
    }

    // MARK: - Cadence

    @Test("The cadence bounds are the documented 60 s active / 120 s freshness pair")
    func cadenceBoundsMatchTheDocumentedContract() {
        // `Documentation/curfew-sync.md` §"Sync model": "Heartbeats reuse the
        // F14 / F15 cadence (60 s active, 120 s freshness threshold)."
        #expect(DeviceStatusReportingPolicy.heartbeatFloorSeconds == 60)
        #expect(DeviceStatusReportingPolicy.heartbeatCeilingSeconds == 120)
    }

    @Test("The default cadence is the documented active cadence")
    func defaultCadenceIsTheActiveCadence() {
        #expect(DeviceStatusReportingPolicy.default.heartbeatSeconds == 60)
    }

    @Test("No settable cadence can exceed the coordinator's freshness threshold")
    func cadenceIsClampedIntoTheFreshnessWindow() {
        // The property that matters: a device cannot be configured to publish
        // less often than a coordinator waits before calling it stale, because
        // that device reads as offline between its own heartbeats.
        let tooSlow = DeviceStatusReportingPolicy(
            isEnabled: true,
            baseURL: "https://coordinator.example",
            deviceToken: "",
            deviceID: "",
            heartbeatSeconds: 3600
        )
        #expect(tooSlow.heartbeatSeconds == 120)

        let tooFast = DeviceStatusReportingPolicy(
            isEnabled: true,
            baseURL: "https://coordinator.example",
            deviceToken: "",
            deviceID: "",
            heartbeatSeconds: 1
        )
        #expect(tooFast.heartbeatSeconds == 60)
    }

    @Test("A persisted out-of-range cadence is corrected on decode, not honoured")
    func decodedCadenceIsClamped() throws {
        // Covers the upgrade path off the build that shipped a 300 s default:
        // that value is in real preferences files and must not survive.
        let stored = Data("""
        {"isEnabled":true,"baseURL":"https://coordinator.example",\
        "deviceToken":"","deviceID":"","heartbeatSeconds":300}
        """.utf8)

        let policy = try JSONDecoder().decode(DeviceStatusReportingPolicy.self, from: stored)

        #expect(policy.heartbeatSeconds == 120)
    }

    // MARK: - Off by default

    @Test("The factory default talks to nobody")
    func defaultPolicyIsSilent() {
        let policy = DeviceStatusReportingPolicy.default

        #expect(!policy.isEnabled)
        #expect(policy.baseURL.isEmpty)
        #expect(policy.deviceToken.isEmpty)
        #expect(policy.deviceID.isEmpty)
        #expect(policy.resolvedEndpoint == nil)
    }
}
