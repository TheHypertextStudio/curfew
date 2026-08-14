@testable import Curfew
import Foundation
import XCTest

final class AccountWakeReleaseTests: XCTestCase {
    private let campaignID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d34")!
    private let deviceID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d35")!
    private let templateID = UUID(uuidString: "018f4f45-cafe-7f00-9a82-e47805fb4d36")!
    private let campaignStart = Date(timeIntervalSince1970: 1_800_000_000)

    func testReleasePolicyCannotCarryBothFixedUnlockAndWakeCampaignFields() throws {
        let fixed = try MorningReleasePolicy.fixedUnlock(
            timeZone: "America/Los_Angeles",
            localUnlockTime: "08:00"
        )
        XCTAssertEqual(fixed.kind, .fixedUnlock)
        XCTAssertEqual(fixed.localUnlockTime, "08:00")
        XCTAssertNil(fixed.campaignTemplateID)

        let wake = try MorningReleasePolicy.wakeCampaign(
            campaignTemplateID: templateID,
            timeZone: "America/Los_Angeles",
            localStartTime: "07:30"
        )
        XCTAssertEqual(wake.kind, .wakeCampaign)
        XCTAssertNil(wake.localUnlockTime)
        XCTAssertEqual(wake.campaignTemplateID, templateID)

        XCTAssertThrowsError(
            try MorningReleasePolicy(
                kind: .wakeCampaign,
                timeZone: "America/Los_Angeles",
                localUnlockTime: "08:00",
                campaignTemplateID: templateID,
                localStartTime: "07:30"
            )
        )
    }

    func testEarlyCampaignPersistsAndPendingHoldsUntilDeterministicDeadline() throws {
        let deadline = campaignStart.addingTimeInterval(16 * 60)
        let update = wakeUpdate(
            state: .scheduled,
            finalDeadline: deadline,
            statusVersion: 1
        )
        var ledger = AccountWakeLedger()

        try ledger.accept(update, now: campaignStart.addingTimeInterval(-8 * 60 * 60))

        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: deadline,
            kind: .accountWakeCampaign,
            campaignID: campaignID
        )
        let decision = WakeReleaseEngine().decision(
            at: campaignStart.addingTimeInterval(60),
            deadline: record,
            wakeStatus: ledger.current,
            remoteOverride: nil,
            localDeviceID: deviceID
        )

        XCTAssertEqual(decision, .hold(until: deadline))
    }

    func testTerminalSatisfiedAndExhaustedStatesReleaseImmediately() {
        for state in [AccountWakeCampaignState.satisfied, .exhausted] {
            let update = wakeUpdate(
                state: state,
                finalDeadline: campaignStart.addingTimeInterval(16 * 60),
                statusVersion: 2
            )
            let record = LockoutDeadlineRecord(
                lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
                scheduledUnlockAt: update.finalDeadlineAt,
                kind: .accountWakeCampaign,
                campaignID: campaignID
            )

            let decision = WakeReleaseEngine().decision(
                at: campaignStart.addingTimeInterval(2 * 60),
                deadline: record,
                wakeStatus: update,
                remoteOverride: nil,
                localDeviceID: deviceID
            )

            XCTAssertEqual(decision, .release(state == .satisfied ? .satisfied : .exhausted))
        }
    }

    func testOfflineDeadlineReleasesWithoutCoordinatorState() {
        let deadline = campaignStart.addingTimeInterval(16 * 60)
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: deadline,
            kind: .accountWakeCampaign,
            campaignID: campaignID
        )

        let decision = WakeReleaseEngine().decision(
            at: deadline,
            deadline: record,
            wakeStatus: nil,
            remoteOverride: nil,
            localDeviceID: deviceID
        )

        XCTAssertEqual(decision, .release(.finalDeadline))
    }

    func testOnlyCurrentAuthorizedOverrideCanReleaseThisDevice() {
        let deadline = campaignStart.addingTimeInterval(16 * 60)
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: deadline,
            kind: .accountWakeCampaign,
            campaignID: campaignID
        )
        let now = campaignStart.addingTimeInterval(3 * 60)
        let active = AccountRemoteOverride(
            overrideID: UUID(),
            requestID: UUID(),
            targetDeviceIDs: [deviceID],
            reason: "A verified remote release for this morning campaign.",
            durationMinutes: 5,
            startsAt: now.addingTimeInterval(-60),
            authorizedBy: .freshWebAAL2,
            status: .active
        )
        let wrongDevice = AccountRemoteOverride(
            overrideID: UUID(),
            requestID: UUID(),
            targetDeviceIDs: [UUID()],
            reason: "A verified remote release for a different device.",
            durationMinutes: 5,
            startsAt: now.addingTimeInterval(-60),
            authorizedBy: .freshWebAAL2,
            status: .active
        )

        XCTAssertEqual(
            WakeReleaseEngine().decision(
                at: now,
                deadline: record,
                wakeStatus: wakeUpdate(
                    state: .ringingAttempt,
                    finalDeadline: deadline,
                    statusVersion: 2
                ),
                remoteOverride: active,
                localDeviceID: deviceID
            ),
            .release(.authorizedOverride)
        )
        XCTAssertEqual(
            WakeReleaseEngine().decision(
                at: now,
                deadline: record,
                wakeStatus: nil,
                remoteOverride: wrongDevice,
                localDeviceID: deviceID
            ),
            .hold(until: deadline)
        )
    }

    func testLedgerRejectsStatusVersionRollbackAndDeadlineMutation() throws {
        var ledger = AccountWakeLedger()
        let current = wakeUpdate(
            state: .ringingAttempt,
            finalDeadline: campaignStart.addingTimeInterval(16 * 60),
            statusVersion: 4
        )
        try ledger.accept(current, now: campaignStart)

        XCTAssertThrowsError(
            try ledger.accept(
                wakeUpdate(
                    state: .satisfied,
                    finalDeadline: current.finalDeadlineAt,
                    statusVersion: 4
                ),
                now: campaignStart
            )
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .staleStatusVersion) }

        XCTAssertThrowsError(
            try ledger.accept(
                wakeUpdate(
                    state: .satisfied,
                    finalDeadline: current.finalDeadlineAt.addingTimeInterval(60),
                    statusVersion: 5
                ),
                now: campaignStart
            )
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .deadlineChanged) }
    }

    func testAccountEnrollmentMakesAccountSyncCanonical() throws {
        let accountFree = AccountSyncConfiguration.accountFree
        let enrolled = try AccountSyncConfiguration(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: campaignStart
            ),
            releasePolicy: .wakeCampaign(
                campaignTemplateID: templateID,
                timeZone: "America/Los_Angeles",
                localStartTime: "07:30"
            )
        )

        XCTAssertEqual(SyncAuthorityResolver.resolve(account: accountFree), .localOnly)
        XCTAssertEqual(SyncAuthorityResolver.resolve(account: enrolled), .curfewAccount)
        XCTAssertFalse(SyncAuthorityResolver.allowsCloudKit(account: enrolled))
    }

    func testLegacySettingsDecodeAsAccountFreeAndEnrollmentRoundTrips() throws {
        let legacyData = try JSONEncoder().encode(CurfewSettings.default)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "accountSync")
        let decodedLegacy = try JSONDecoder().decode(
            CurfewSettings.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        XCTAssertEqual(decodedLegacy.accountSync, .accountFree)

        var enrolled = decodedLegacy
        enrolled.accountSync = try AccountSyncConfiguration(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: campaignStart
            ),
            releasePolicy: .wakeCampaign(
                campaignTemplateID: templateID,
                timeZone: "America/Los_Angeles",
                localStartTime: "07:30"
            )
        )
        let roundTrip = try JSONDecoder().decode(
            CurfewSettings.self,
            from: JSONEncoder().encode(enrolled)
        )
        XCTAssertEqual(roundTrip.accountSync, enrolled.accountSync)
    }

    func testReleasePolicyDecodeRevalidatesMutuallyExclusiveAuthority() throws {
        let invalid = """
        {
          "kind": "wake_campaign",
          "timeZone": "America/Los_Angeles",
          "localUnlockTime": "08:00",
          "campaignTemplateID": "\(templateID.uuidString)",
          "localStartTime": "07:30"
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                MorningReleasePolicy.self,
                from: Data(invalid.utf8)
            )
        )
    }

    func testWakeLedgerStoreSurvivesRestartAndPreservesRollbackGate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-wake-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AccountWakeLedgerStore(recordURL: url)
        var ledger = AccountWakeLedger()
        let accepted = wakeUpdate(
            state: .ringingAttempt,
            finalDeadline: campaignStart.addingTimeInterval(16 * 60),
            statusVersion: 4
        )
        try ledger.accept(accepted, now: campaignStart)
        try store.save(ledger)

        var restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.current, accepted)
        XCTAssertThrowsError(
            try restored.accept(
                wakeUpdate(
                    state: .satisfied,
                    finalDeadline: accepted.finalDeadlineAt,
                    statusVersion: 4
                ),
                now: campaignStart
            )
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .staleStatusVersion) }
    }

    func testEveningBoundaryUsesEarlyCampaignDeadlineInsteadOfFixedUnlock() throws {
        let legacyUnlock = campaignStart.addingTimeInterval(30 * 60)
        let campaignDeadline = campaignStart.addingTimeInterval(16 * 60)
        let account = try AccountSyncConfiguration(
            enrollment: AccountDeviceEnrollment(
                deviceID: deviceID,
                keyEpoch: 1,
                enrolledAt: campaignStart.addingTimeInterval(-30 * 24 * 60 * 60)
            ),
            releasePolicy: .wakeCampaign(
                campaignTemplateID: templateID,
                timeZone: "America/Los_Angeles",
                localStartTime: "07:30"
            )
        )

        let record = WakeLockoutDeadlineResolver.record(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduleUnlockAt: legacyUnlock,
            account: account,
            wakeStatus: wakeUpdate(
                state: .scheduled,
                finalDeadline: campaignDeadline,
                statusVersion: 1
            )
        )

        XCTAssertEqual(record.kind, .accountWakeCampaign)
        XCTAssertEqual(record.campaignID, campaignID)
        XCTAssertEqual(record.scheduledUnlockAt, campaignDeadline)
    }

    private func wakeUpdate(
        state: AccountWakeCampaignState,
        finalDeadline: Date,
        statusVersion: Int
    ) -> AccountWakeStatusUpdate {
        AccountWakeStatusUpdate(
            campaignID: campaignID,
            state: state,
            attemptNumber: state == .scheduled ? 0 : 1,
            maximumAttempts: 3,
            selectedDeviceIDs: [deviceID],
            finalDeadlineAt: finalDeadline,
            statusVersion: statusVersion,
            updatedAt: campaignStart
        )
    }
}
