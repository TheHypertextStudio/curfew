@testable import Curfew
import Foundation
import Testing

/// The credential half of the reporting wiring: what Curfew signs a status
/// report with, and what it does when it cannot sign one.
///
/// Split from `DeviceStatusWiringTests` because they answer different
/// questions — that file is about *when* a report happens, this one about
/// *whether it may*.
@MainActor
struct DeviceStatusCredentialWiringTests {
    // MARK: - What goes on the wire

    @Test("The report carries a signed assertion for this device")
    func reportCarriesThisDevicesAssertion() async throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        let call = try #require(harness.transport.calls.first)
        // A `CompactJWS`, not the pasted opaque token an earlier build sent —
        // `verifyRequestAssertion` can actually parse this one.
        #expect(matches(call.bearerToken, DeviceIdentityAssertionTests.compactJWSPattern))

        // And it is this device's assertion: same account, same device
        // identifier as the publication beside it, which is what keeps the
        // route from answering `403 device_mismatch`.
        let claims = try #require(decodedClaims(from: call.bearerToken))
        #expect(claims["userId"] as? String == DeviceStatusWiringHarness.userID)
        #expect(claims["deviceId"] as? String == DeviceStatusWiringHarness.deviceID)
        #expect(claims["audience"] as? String == "curfew-user-coordinator")
        let body = try #require(harness.transport.decodedBody(at: 0))
        #expect(claims["deviceId"] as? String == body["deviceId"] as? String)
    }

    @Test("Each report is signed afresh rather than reusing one assertion")
    func eachReportIsSignedAfresh() async throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )
        let model = harness.model

        model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()
        // A later publish, minted at a later instant. The window is two
        // minutes, so a device that signed once at launch and cached it would
        // start failing after two minutes of uptime.
        model.currentTime = model.currentTime.addingTimeInterval(300)
        model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        let tokens = harness.transport.calls.map(\.bearerToken)
        try #require(tokens.count == 2)
        #expect(tokens[0] != tokens[1])
    }

    // MARK: - The credential gate

    @Test("A model with an endpoint but no shared secret publishes nothing, ever")
    func unsetSecretPublishesNothing() async {
        // Everything else is configured: reporting on, HTTPS address, account,
        // device identifier. The only missing piece is the secret, and that
        // alone must keep this Mac silent — a report it cannot sign is a
        // guaranteed 401, and sending it would put a device identifier and a
        // schedule digest on someone's network for nothing.
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(),
            secret: ""
        )

        harness.model.publishDeviceStatus(trigger: .configuration)
        for _ in 0 ..< 20 {
            harness.model.tick()
        }
        await harness.settle()

        #expect(harness.transport.calls.isEmpty)
        #expect(!harness.model.isDeviceStatusReportingLive)
    }

    @Test("Filling in the secret is what starts publishing")
    func configuringTheSecretStartsPublishing() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(),
            secret: ""
        )

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()
        #expect(harness.transport.calls.isEmpty)

        // The same model, one setting later. Proves the silence above was the
        // credential's doing and not something else about the harness.
        harness.model.deviceAssertionSecret = DeviceStatusWiringHarness.secret
        #expect(harness.model.isDeviceStatusReportingLive)
        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()
        #expect(harness.transport.calls.count == 1)
    }

    @Test("A model with a secret but no account publishes nothing")
    func unsetAccountPublishesNothing() async {
        // `userId` is `minLength: 1` in `InternalDeviceIdentityClaims`, and the
        // route writes it onto the device row — an assertion without one is not
        // a schema-valid credential.
        var reporting = DeviceStatusWiringHarness.configured()
        reporting.userID = ""
        let harness = DeviceStatusWiringHarness(reporting: reporting)

        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        #expect(harness.transport.calls.isEmpty)
        #expect(!harness.model.isDeviceStatusReportingLive)
    }

    @Test("An unsigned attempt does not consume a status version")
    func unsignedPublishDoesNotBurnAVersion() async {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured(),
            secret: ""
        )

        for _ in 0 ..< 3 {
            harness.model.publishDeviceStatus(trigger: .configuration)
        }
        await harness.settle()
        harness.model.deviceAssertionSecret = DeviceStatusWiringHarness.secret
        harness.model.publishDeviceStatus(trigger: .configuration)
        await harness.settle()

        // The first report a coordinator ever sees from this device is v0. Had
        // the unconfigured attempts advanced the counter, this device would
        // look to the coordinator as though it had lost its first publications.
        #expect(harness.transport.publishedVersions == [0])
    }

    @Test("The secret is never written into the settings blob")
    func secretDoesNotReachTheSettingsStore() throws {
        let harness = DeviceStatusWiringHarness(
            reporting: DeviceStatusWiringHarness.configured()
        )
        harness.model.deviceAssertionSecret = "a-secret-that-must-not-be-persisted"

        // The whole point of the Keychain store: whatever the settings plist
        // holds, it does not hold this. Encoded rather than inspected key by
        // key so a future field cannot smuggle it back in.
        let encoded = try JSONEncoder().encode(harness.model.settings)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("a-secret-that-must-not-be-persisted"))
    }

    // MARK: - Helpers

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// The claims out of a compact JWS, without verifying it — the signature is
    /// `DeviceIdentityAssertionTests`' subject; this file is about wiring.
    private func decodedClaims(from compactJWS: String) -> [String: Any]? {
        let segments = compactJWS.split(separator: ".").map(String.init)
        guard segments.count == 3 else { return nil }
        var padded = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
