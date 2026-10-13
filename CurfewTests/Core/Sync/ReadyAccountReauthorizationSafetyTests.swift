@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
extension AccountEnrollmentReauthorizationTests {
    @Test("Duplicate reconnect taps keep the first sign-in cancellable")
    func duplicateReadyReconnectIsSingleFlight() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        try fixture.pending.markReady(fixture.enrollment)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-single-flight-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteEnrollment = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("remote-command-enrollment.json")
        )
        try remoteEnrollment.save(RemoteCommandEnrollment(
            userID: "original-account",
            deviceID: fixture.enrollment.deviceID
        ))
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        oauth.suspendFirstAttempt = true
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: ReauthorizationDeviceFixture(enrollment: fixture.enrollment),
            remoteCommandEnrollmentStore: remoteEnrollment
        )

        let first = Task { await controller.reconnectEnrolledMac(fixture.enrollment) }
        for _ in 0 ..< 1000 where oauth.suspended == nil {
            await Task.yield()
        }
        #expect(oauth.suspended != nil)
        await controller.reconnectEnrolledMac(fixture.enrollment)
        #expect(oauth.reauthorizeCount == 1)
        #expect(controller.state == .signingIn)

        controller.cancelSignIn()
        oauth.resumeFirstAttempt()
        let renewed = await first.value
        #expect(!renewed)
        #expect(controller.state == .ready(fixture.enrollment))
        #expect(try fixture.secrets.data(for: "oauth-refresh-token") == Data("old-refresh".utf8))
    }

    @Test("Saved settings can renew the original account after the ready marker disappears")
    func savedSettingsWithoutReadyMarkerRenewSafely() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        try fixture.pending.markReady(fixture.enrollment)
        try fixture.secrets.delete("pending-account-enrollment-ready")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-missing-ready-marker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteEnrollment = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("remote-command-enrollment.json")
        )
        try remoteEnrollment.save(RemoteCommandEnrollment(
            userID: "original-account",
            deviceID: fixture.enrollment.deviceID
        ))
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices,
            remoteCommandEnrollmentStore: remoteEnrollment
        )
        #expect(controller.state == .accountFree)

        let renewed = await controller.reconnectEnrolledMac(fixture.enrollment)

        #expect(renewed)
        #expect(controller.state == .ready(fixture.enrollment))
        #expect(try fixture.pending.load() == .ready(fixture.enrollment))
        #expect(oauth.expectedAccountUserID == "original-account")
        #expect(devices.enrollCount == 0)
    }

    @Test("An enrolled Mac cannot renew without its matching owner record")
    func readyMacWithoutMatchingOwnerFailsClosed() async throws {
        let fixture = try makeFixture(accountUserID: "original-account")
        try fixture.pending.markReady(fixture.enrollment)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-unanchored-reauth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteEnrollment = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("remote-command-enrollment.json")
        )
        try remoteEnrollment.save(RemoteCommandEnrollment(
            userID: "original-account",
            deviceID: UUID()
        ))
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices,
            remoteCommandEnrollmentStore: remoteEnrollment
        )

        await controller.signIn()

        #expect(controller.state == .ready(fixture.enrollment))
        #expect(controller.enrollmentRetryError?.contains("account") == true)
        #expect(oauth.reauthorizeCount == 0)
        #expect(devices.enrollCount == 0)
        #expect(try fixture.secrets.data(for: "oauth-refresh-token") == Data("old-refresh".utf8))
    }
}
