import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import XCTest

@MainActor
final class HeadlessAccountOAuthTests: XCTestCase {
    func testSignInWithoutWindowProvidesAuthorizationURL() async throws {
        let service = AccountOAuthEnrollmentService(
            secretStore: NativeTransportMemorySecretStore(),
            endpoints: .staging,
            callbackRouter: AccountOAuthCallbackRouter()
        )
        var authorizationURL: URL?

        do {
            _ = try await service.signIn(presentationWindow: nil) { url in
                authorizationURL = url
                Task { @MainActor in service.cancelSignIn() }
            }
        } catch {}

        let url = try XCTUnwrap(authorizationURL, "Headless sign-in must offer the browser URL")
        XCTAssertEqual(url.host, CurfewServiceEndpoints.staging.accountOrigin.host)
    }
}
