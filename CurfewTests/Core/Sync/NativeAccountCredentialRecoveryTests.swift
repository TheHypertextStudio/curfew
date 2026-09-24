@testable import Curfew
import Foundation
import XCTest

@MainActor
final class NativeAccountCredentialRecoveryTests: XCTestCase {
    func testMissingAccessCredentialRequestsReauthorization() async throws {
        let secrets = EnrollmentRecoveryMemorySecretStore()
        let service = NativeAccountDeviceEnrollmentService(
            secretStore: secrets,
            endpoints: .staging
        )
        let grant = AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "old-access", refreshToken: "old-refresh"),
            state: "state",
            codeChallenge: "challenge",
            subjectID: "original-account"
        )

        do {
            _ = try await service.enroll(grant: grant, deviceID: UUID())
            XCTFail("missing credentials must request reauthorization")
        } catch AccountOAuthTokenRefreshError.missingCredentials {
            // The controller can offer a fresh sign-in without discarding the saved device.
        }
    }
}
