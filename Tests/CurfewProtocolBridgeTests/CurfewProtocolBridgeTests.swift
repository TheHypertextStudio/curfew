import CurfewKit
import CurfewProtocolBridge
import CurfewProtocols
import XCTest

final class CurfewProtocolBridgeTests: XCTestCase {
    private let campaignID = "018f4f45-cafe-7f00-9a82-e47805fb4d34"
    private let deviceID = "018f4f45-cafe-7f00-9a82-e47805fb4d35"

    func testGeneratedWakePolicyMapsWithoutInventingFields() throws {
        let generated = CurfewProtocols.ReleasePolicy(
            dstResolution: .init(gap: .firstValidInstant, overlap: .firstOccurrence),
            kind: .wakeCampaign,
            localUnlockTime: nil,
            timeZone: "America/Los_Angeles",
            campaignTemplateID: campaignID,
            localStartTime: "07:30"
        )

        let local = try ProtocolV2Bridge.releasePolicy(generated)

        XCTAssertEqual(local.kind, .wakeCampaign)
        XCTAssertEqual(local.campaignTemplateID?.uuidString.lowercased(), campaignID)
        XCTAssertNil(local.localUnlockTime)
    }

    func testGeneratedWakeStatusMapsAsAuthenticatedServerMetadata() throws {
        let generatedStatus = CurfewProtocols.WakeStatus(
            attemptNumber: 1,
            campaignID: campaignID,
            selectedDeviceIDS: [deviceID],
            state: .ringingAttempt,
            statusVersion: 4,
            updatedAt: "2027-01-15T15:31:00Z"
        )
        let local = try ProtocolV2Bridge.wakeStatus(generatedStatus)

        XCTAssertEqual(local.campaignID.uuidString.lowercased(), campaignID)
        XCTAssertEqual(local.state, .ringingAttempt)
        XCTAssertEqual(local.statusVersion, 4)
    }

    func testGeneratedRemoteOverrideMapsAuthorizationAndBounds() throws {
        let generated = CurfewProtocols.RemoteOverride(
            authorizedBy: .mcpUserApproval,
            durationMinutes: 15,
            overrideID: "018f4f45-cafe-7f00-9a82-e47805fb4d36",
            reason: "Freshly approved override",
            requestID: "018f4f45-cafe-7f00-9a82-e47805fb4d37",
            startsAt: "2027-01-15T15:33:00Z",
            status: .active,
            targetDeviceIDS: [deviceID]
        )

        let local = try ProtocolV2Bridge.remoteOverride(generated)

        XCTAssertEqual(local.authorizedBy, .mcpUserApproval)
        XCTAssertEqual(local.durationMinutes, 15)
        XCTAssertEqual(local.targetDeviceIDs.first?.uuidString.lowercased(), deviceID)
    }

    func testRejectsMalformedWakeStatusIdentifier() {
        let status = CurfewProtocols.WakeStatus(
            attemptNumber: 0,
            campaignID: "not-a-uuid",
            selectedDeviceIDS: [deviceID],
            state: .scheduled,
            statusVersion: 1,
            updatedAt: "2027-01-15T15:30:00Z"
        )
        XCTAssertThrowsError(try ProtocolV2Bridge.wakeStatus(status))
    }
}
