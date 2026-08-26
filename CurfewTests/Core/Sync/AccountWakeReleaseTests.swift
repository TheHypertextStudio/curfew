@testable import Curfew
import Foundation
import XCTest

// The scenarios share one transport and ledger fixture so they can assert the
// complete wake-release contract without duplicating security setup.
// swiftlint:disable:next type_body_length
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

    func testEarlyCampaignPersistsAndPendingHoldsUntilVerifiedRelease() throws {
        let update = wakeUpdate(state: .scheduled, statusVersion: 1)
        var ledger = AccountWakeLedger()

        try ledger.accept(update, now: campaignStart.addingTimeInterval(-8 * 60 * 60))

        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: .distantFuture,
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

        XCTAssertEqual(decision, .hold(until: .distantFuture))
    }

    func testSatisfiedStateReleasesImmediately() {
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: .distantFuture,
            kind: .accountWakeCampaign,
            campaignID: campaignID
        )

        let decision = WakeReleaseEngine().decision(
            at: campaignStart.addingTimeInterval(2 * 60),
            deadline: record,
            wakeStatus: wakeUpdate(state: .satisfied, statusVersion: 2),
            remoteOverride: nil,
            localDeviceID: deviceID
        )

        XCTAssertEqual(decision, .release(.satisfied))
    }

    // The cases keep every rejection reason beside the accepted override.
    // swiftlint:disable:next function_body_length
    func testOnlyCurrentAuthorizedOverrideCanReleaseThisDevice() {
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: campaignStart.addingTimeInterval(-12 * 60 * 60),
            scheduledUnlockAt: .distantFuture,
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
            .hold(until: .distantFuture)
        )
    }

    func testLedgerRejectsStatusVersionRollbackAndTerminalRollback() throws {
        var ledger = AccountWakeLedger()
        let current = wakeUpdate(
            state: .ringingAttempt,
            statusVersion: 4
        )
        try ledger.accept(current, now: campaignStart)

        XCTAssertThrowsError(
            try ledger.accept(
                wakeUpdate(
                    state: .satisfied,
                    statusVersion: 4
                ),
                now: campaignStart
            )
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .staleStatusVersion) }

        try ledger.accept(wakeUpdate(state: .satisfied, statusVersion: 5), now: campaignStart)
        XCTAssertThrowsError(
            try ledger.accept(wakeUpdate(state: .ringingAttempt, statusVersion: 6), now: campaignStart)
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .terminalRollback) }
    }

    func testLedgerAcceptsUnboundedAttempts() throws {
        var ledger = AccountWakeLedger()
        try ledger.accept(
            wakeUpdate(state: .ringingAttempt, statusVersion: 1, attemptNumber: 10_000),
            now: campaignStart
        )
        XCTAssertEqual(ledger.current?.attemptNumber, 10_000)
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
                    statusVersion: 4
                ),
                now: campaignStart
            )
        ) { XCTAssertEqual($0 as? AccountWakeLedgerError, .staleStatusVersion) }
    }

    func testEveningBoundaryUsesNoDeadlineCampaignInsteadOfFixedUnlock() throws {
        let legacyUnlock = campaignStart.addingTimeInterval(30 * 60)
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
            wakeStatus: wakeUpdate(state: .scheduled, statusVersion: 1)
        )

        XCTAssertEqual(record.kind, .accountWakeCampaign)
        XCTAssertEqual(record.campaignID, campaignID)
        XCTAssertEqual(record.scheduledUnlockAt, .distantFuture)
    }

    private func wakeUpdate(
        state: AccountWakeCampaignState,
        statusVersion: Int,
        attemptNumber: Int? = nil
    ) -> AccountWakeStatusUpdate {
        AccountWakeStatusUpdate(
            campaignID: campaignID,
            state: state,
            attemptNumber: attemptNumber ?? (state == .scheduled ? 0 : 1),
            selectedDeviceIDs: [deviceID],
            statusVersion: statusVersion,
            updatedAt: campaignStart
        )
    }
}
