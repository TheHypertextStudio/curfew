@testable import Curfew
@testable import CurfewKit
import Foundation
import XCTest

@MainActor
extension NativeAccountSyncTransportTests {
    func testStatusPublicationRefreshesExpiredCredentialsInsteadOfStoppingSync() async throws {
        let fixture = try makeFixture(
            accessToken: "expired-access-token", refreshToken: "rotating-refresh-token",
            clientID: "native-client"
        )
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let enrollment = RemoteCommandEnrollmentStore(recordURL: root
            .appendingPathComponent("enrollment.json"))
        try enrollment.save(RemoteCommandEnrollment(
            userID: "account_018f4f45cafe7f009a82e47805fb4d34", deviceID: fixture.deviceID
        ))
        let events = NativeTransportEventRecorder()
        let published = expectation(description: "status published after shared token refresh")
        installStatusRefreshHandler(events: events, published: published)
        defer { NativeTransportURLProtocol.handler = nil }
        let transport = makeTransport(secrets: fixture.secrets, enrollmentStore: enrollment)

        transport.publishDeviceStatus(
            Self.statusReport(deviceID: fixture.deviceID, statusVersion: 17),
            deviceID: fixture.deviceID
        )

        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(events.values, ["expired", "refresh", "status"])
        XCTAssertEqual(
            try stringSecret("oauth-access-token", in: fixture.secrets),
            "fresh-access-token"
        )
        await transport.disconnectAndWaitForPendingOperations()
    }

    private func installStatusRefreshHandler(
        events: NativeTransportEventRecorder,
        published: XCTestExpectation
    ) {
        NativeTransportURLProtocol.handler = { request in
            if request.url?.path == "/api/auth/oauth2/token" {
                events.append("refresh")
                return Self.freshTokensResponse(for: request)
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access-token" {
                events.append("expired")
                return (401, Data())
            }
            switch request.url?.path {
            case "/sync/device-proof/challenge": return Self.challengeResponse()
            case "/sync/status":
                events.append("status")
                published.fulfill()
                return (204, Data())
            default: throw NativeAccountSyncError.invalidResponse
            }
        }
    }
}
