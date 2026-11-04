@testable import Curfew
import Foundation
import XCTest

@MainActor
final class AccountOAuthProcessLockTests: XCTestCase {
    func testSeparateAuthenticationSessionsAreSingleFlight() throws {
        let first = AccountOAuthAuthenticationGate()
        let second = AccountOAuthAuthenticationGate()
        try first.begin()
        defer { first.finish() }

        XCTAssertThrowsError(try second.begin()) { error in
            guard case AccountOAuthEnrollmentError.authenticationInProgress = error else {
                return XCTFail("Expected an active sign-in error")
            }
        }
    }
}
