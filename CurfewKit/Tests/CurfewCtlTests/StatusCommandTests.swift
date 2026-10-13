@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct StatusCommandTests {
    @Test("Disarmed observed state cannot be printed as a scheduled lock")
    func disarmedStatusIsUnknown() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let observation = CurfewObservedStatus(
            evaluation: .locked(
                lockDate: now,
                unlockDate: now.addingTimeInterval(300)
            ),
            observedAt: now,
            enforcementRunning: false,
            ownsLockout: false
        )

        let payload = StatusCommand.jsonObject(from: observation)

        #expect(payload["phase"] as? String == "unknown")
        #expect(payload["lock_date"] == nil)
        #expect(payload["unlock_date"] == nil)
        #expect(payload["minutes_remaining"] == nil)
    }
}
