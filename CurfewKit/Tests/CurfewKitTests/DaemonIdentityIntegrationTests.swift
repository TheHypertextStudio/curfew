@testable import CurfewKit
import Foundation
import Testing

struct DaemonIdentityIntegrationTests {
    @Test func transportIdentitiesRemainFlavorSpecific() throws {
        for flavor in CurfewFlavor.allCases {
            let identity = try #require(DaemonSigningIdentity(
                flavor: flavor,
                teamIdentifier: "SYNTHETIC1"
            ))
            #expect(identity.machServiceName == flavor.daemonLabel)
            #expect(identity.clientRequirement
                .contains("identifier \"studio.hypertext.curfew\(flavor.identifierSuffix)\""))
            #expect(identity.serverRequirement.contains("identifier \"curfew-daemon\""))
            #expect(identity.clientRequirement.contains("SYNTHETIC1"))
        }
        #expect(DaemonSigningIdentity(flavor: .production, teamIdentifier: nil) == nil)
        #expect(DaemonSigningIdentity(flavor: .production, teamIdentifier: "bad\" or true") == nil)
    }

    @Test func resolvingRepeatedlyPreservesStrongestIdentity() {
        let now = Date(timeIntervalSince1970: 1000)
        let campaign = UUID()
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .accountWakeCampaign, campaignID: campaign
        )
        let first = DaemonLockoutDeadlineResolver.resolve(
            now: now, user: record, shadow: nil, remote: nil
        )
        let second = DaemonLockoutDeadlineResolver.resolve(
            now: now, user: record, shadow: first, remote: nil
        )
        #expect(first?.lockoutID == record.lockoutID)
        #expect(second?.lockoutID == record.lockoutID)
        #expect(second?.campaignID == campaign)
    }

    @Test func campaignAndIdentitySurviveEncoding() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(600),
            kind: .accountWakeCampaign, campaignID: UUID()
        )
        let restored = try JSONDecoder().decode(
            LockoutDeadlineRecord.self, from: JSONEncoder().encode(record)
        )
        #expect(restored == record)
    }

    @Test func replayingAResultPreservesCommandIdentity() {
        let now = Date(timeIntervalSince1970: 1000)
        let device = UUID()
        let result = RemoteCommandResult(
            commandID: UUID(),
            deviceID: device,
            sequence: 1,
            stage: .applied,
            resolvedAt: now,
            appliedDeadline: now.addingTimeInterval(600)
        )
        let first = RemoteCommandLockoutProjection.resolve(
            result: result,
            enrolledDeviceID: device,
            now: now,
            current: nil
        )
        let replay = RemoteCommandLockoutProjection.resolve(
            result: result,
            enrolledDeviceID: device,
            now: now,
            current: first
        )
        #expect(first?.lockoutID == result.commandID)
        #expect(replay?.lockoutID == result.commandID)
    }
}
