import Foundation
import Testing
@testable import CurfewKit

struct DaemonIdentityIntegrationTests {
    @Test func resolvingRepeatedlyPreservesStrongestIdentity() {
        let now = Date(timeIntervalSince1970: 1_000)
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
        let now = Date(timeIntervalSince1970: 1_000)
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
}
