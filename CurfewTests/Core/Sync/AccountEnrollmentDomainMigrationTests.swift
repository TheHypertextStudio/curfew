@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

extension AccountEnrollmentReauthorizationTests {
    @Test(
        "Old-domain authorization reconnects the same Mac without replacing its keys",
        arguments: [false, true]
    )
    func domainMigrationRetainsSavedMac(hasPreviousMarker: Bool) async throws {
        let fixture = try makeOldDomainFixture(hasPreviousMarker: hasPreviousMarker)
        try fixture.pending.markReady(fixture.enrollment)
        let keys = AccountDeviceKeyStore(secretStore: fixture.secrets)
        _ = try keys.createEnrollment(
            deviceID: fixture.enrollment.deviceID,
            keyEpoch: fixture.enrollment.keyEpoch,
            createdAt: fixture.enrollment.enrolledAt
        )
        let originalKeys = try #require(keys.load(deviceID: fixture.enrollment.deviceID))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-domain-reauth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteEnrollment = RemoteCommandEnrollmentStore(
            recordURL: root.appendingPathComponent("enrollment.json")
        )
        let owner = RemoteCommandEnrollment(
            userID: "original-account",
            deviceID: fixture.enrollment.deviceID
        )
        try remoteEnrollment.save(owner)
        let oauth = ReauthorizationOAuthFixture(secretStore: fixture.secrets)
        let devices = ReauthorizationDeviceFixture(enrollment: fixture.enrollment)
        let controller = AccountEnrollmentController(
            secretStore: fixture.secrets,
            oauth: oauth,
            devices: devices,
            remoteCommandEnrollmentStore: remoteEnrollment
        )

        #expect(controller.state == .ready(fixture.enrollment))
        #expect(controller.requiresReauthorization)
        #expect(try fixture.secrets.data(for: "oauth-access-token") == nil)
        #expect(try fixture.secrets.data(for: "oauth-refresh-token") == nil)

        await controller.signIn()

        #expect(controller.state == .ready(fixture.enrollment))
        #expect(!controller.requiresReauthorization)
        #expect(try fixture.pending.load() == .ready(fixture.enrollment))
        #expect(try remoteEnrollment.load()?.userID == "original-account")
        #expect(try remoteEnrollment.load()?.deviceID == fixture.enrollment.deviceID)
        #expect(try keys.load(deviceID: fixture.enrollment.deviceID) == originalKeys)
        #expect(try fixture.secrets.data(for: "oauth-access-token") == Data("new-access".utf8))
        #expect(oauth.expectedAccountUserID == "original-account")
        #expect(devices.enrollCount == 0)
    }

    private func makeOldDomainFixture(hasPreviousMarker: Bool) throws -> ReauthorizationFixture {
        let fixture = try makeFixture(accountUserID: "original-account")
        if hasPreviousMarker {
            let identity = "https://curfew-account-staging.hypertext.studio"
                + "|https://curfew-sync-staging.hypertext.studio"
            try fixture.secrets.save(Data(identity.utf8), for: "oauth-deployment-identity")
        } else {
            try fixture.secrets.delete("oauth-deployment-identity")
        }
        return fixture
    }
}
