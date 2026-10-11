import AppKit
@testable import Curfew
import CurfewKit
import Foundation
import Testing

@MainActor
final class ReauthorizationOAuthFixture: AccountOAuthEnrolling {
    var rejectAsDifferentAccount = false
    var afterPersist: (@MainActor () -> Void)?
    var suspendFirstAttempt = false
    var suspended: CheckedContinuation<Void, Never>?
    private(set) var reauthorizeCount = 0
    private(set) var expectedAccountUserID: String?
    private let secretStore: any AccountSecretStoring

    init(secretStore: any AccountSecretStoring) {
        self.secretStore = secretStore
    }

    func signIn(
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        Issue.record("A saved Mac must not start a new device enrollment")
        throw AccountOAuthEnrollmentError.invalidResponse
    }

    func reauthorize(
        expectedAccountUserID: String,
        presentationWindow _: NSWindow?,
        authorizationURLHandler _: @escaping @MainActor (URL) -> Void
    ) async throws -> AccountOAuthGrant {
        reauthorizeCount += 1
        self.expectedAccountUserID = expectedAccountUserID
        if suspendFirstAttempt, reauthorizeCount == 1 {
            await withCheckedContinuation { suspended = $0 }
        }
        if rejectAsDifferentAccount {
            throw AccountOAuthEnrollmentError.accountMismatch
        }
        try secretStore.save(Data(AccountOAuthOfficialClient.clientID.utf8), for: "oauth-client-id")
        try secretStore.save(Data("new-refresh".utf8), for: "oauth-refresh-token")
        try secretStore.save(Data("new-access".utf8), for: "oauth-access-token")
        afterPersist?()
        return AccountOAuthGrant(
            tokens: AccountOAuthTokens(accessToken: "new-access", refreshToken: "new-refresh"),
            state: "new-state",
            codeChallenge: "new-challenge",
            subjectID: expectedAccountUserID
        )
    }

    func cancelSignIn() {}

    func resumeFirstAttempt() {
        suspended?.resume()
        suspended = nil
    }
}
